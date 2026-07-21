#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sched.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <limits.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/syscall.h>
#include <linux/capability.h>
#include <sys/capability.h>

#include "sd-init-seccomp.h"
#include "sd-init-caps.h"

/* Version for install.sh verification */
#define SD_INIT_VERSION "1.3.14"

/* Syscall wrapper for pivot_root */
static inline int pivot_root(const char *new_root, const char *put_old) {
    return syscall(SYS_pivot_root, new_root, put_old);
}

/* Fail with error message */
#define DIE(msg) do { perror(msg); exit(1); } while(0)

/* Global child PID for signal forwarding (PID 1 init) */
static volatile sig_atomic_t child_pid = 0;

/* Signal handler: forward SIGTERM, SIGINT, SIGQUIT to child */
static void forward_signal(int sig) {
    if (child_pid > 0) {
        kill(child_pid, sig);
    }
}

/* Signal handler: reap zombie children (SIGCHLD) */
static void reap_handler(int sig __attribute__((unused))) {
    int status;
    pid_t pid;
    while ((pid = waitpid(-1, &status, WNOHANG)) > 0) {
        /* Child reaped */
    }
}

typedef struct {
    char *rootfs;
    char *cgroup_path;
    char **caps;
    int caps_count;
    char **env;
    int env_count;
    char **cmd;
    int cmd_count;
} sd_init_config;

/* Parse command-line arguments */
static sd_init_config parse_args(int argc, char *argv[]) {
    sd_init_config cfg = {0};
    int i = 1;

    while (i < argc) {
        if (strcmp(argv[i], "--rootfs") == 0) {
            if (++i >= argc) DIE("--rootfs requires argument");
            cfg.rootfs = argv[i];
        } else if (strcmp(argv[i], "--cgroup") == 0) {
            if (++i >= argc) DIE("--cgroup requires argument");
            cfg.cgroup_path = argv[i];
        } else if (strcmp(argv[i], "--caps") == 0) {
            if (++i >= argc) DIE("--caps requires argument");
            cfg.caps = realloc(cfg.caps, (cfg.caps_count + 1) * sizeof(char*));
            cfg.caps[cfg.caps_count++] = argv[i];
        } else if (strcmp(argv[i], "--env") == 0) {
            if (++i >= argc) DIE("--env requires argument");
            cfg.env = realloc(cfg.env, (cfg.env_count + 1) * sizeof(char*));
            cfg.env[cfg.env_count++] = argv[i];
        } else if (strcmp(argv[i], "--") == 0) {
            i++;
            cfg.cmd_count = argc - i;
            cfg.cmd = argv + i;
            break;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            exit(1);
        }
        i++;
    }

    if (!cfg.rootfs) DIE("--rootfs is required");
    if (!cfg.cmd || cfg.cmd_count == 0) DIE("Command required after --");

    return cfg;
}

/* Close all file descriptors except 0, 1, 2 */
static void close_extra_fds(void) {
    int max_fd = sysconf(_SC_OPEN_MAX);
    for (int fd = 3; fd < max_fd; fd++) {
        close(fd);
    }
}

/* Setup /dev inside container (tmpfs only, no auto-devices) */
static void setup_dev(void) {
    mkdir("dev", 0755);
    /* Use tmpfs instead of devtmpfs (empty by default, no auto-populated devices) */
    mount("tmpfs", "dev", "tmpfs", MS_NOSUID | MS_NOEXEC | MS_NODEV, "mode=0755,size=64m");

    /* Manually create only required device nodes */
    mknod("dev/null", S_IFCHR | 0666, makedev(1, 3));
    mknod("dev/zero", S_IFCHR | 0666, makedev(1, 5));
    mknod("dev/random", S_IFCHR | 0666, makedev(1, 8));
    mknod("dev/urandom", S_IFCHR | 0666, makedev(1, 9));
    mknod("dev/tty", S_IFCHR | 0666, makedev(5, 0));
}

/* Setup /proc with hidepid=2 */
static void setup_proc(void) {
    mkdir("proc", 0555);
    mount("proc", "proc", "proc", MS_NOSUID | MS_NOEXEC | MS_NODEV, "hidepid=2");
}

/* Setup /sys with read-only hardening */
static void setup_sys(void) {
    mkdir("sys", 0555);
    mount("sysfs", "sys", "sysfs", MS_NOSUID | MS_NOEXEC | MS_NODEV, NULL);
    mount(NULL, "sys", NULL, MS_REMOUNT | MS_RDONLY | MS_NOSUID | MS_NOEXEC | MS_NODEV, NULL);
}

/* Mask sensitive /proc paths */
static void mask_proc_paths(void) {
    /* Overlay tmpfs on dangerous /proc subdirectories */
    mkdir("proc/sys", 0555);
    mount("tmpfs", "proc/sys", "tmpfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, "mode=0555");

    mkdir("proc/irq", 0555);
    mount("tmpfs", "proc/irq", "tmpfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, "mode=0555");

    mkdir("proc/bus", 0555);
    mount("tmpfs", "proc/bus", "tmpfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, "mode=0555");
}

/* Mask sensitive paths */
static void mask_paths(void) {
    const char *paths[] = {
        "/proc/sys/kernel/modules",
        "/sys/firmware/efi"
    };
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        if (mount("/dev/null", (char*)paths[i], NULL, MS_BIND, NULL) < 0) {
            /* Path may not exist, ignore */
        }
    }
}

/* Setup /dev/pts and /dev/shm */
static void setup_devpts_shm(void) {
    mkdir("dev/pts", 0755);
    mount("devpts", "dev/pts", "devpts", MS_NOSUID | MS_NOEXEC | MS_NODEV, "newinstance,ptmxmode=0666");

    mkdir("dev/shm", 0777);
    mount("tmpfs", "dev/shm", "tmpfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, "mode=1777,size=128m");
}

/* Setup /tmp and /run */
static void setup_tmp_run(void) {
    mkdir("tmp", 0777);
    mount("tmpfs", "tmp", "tmpfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, "mode=1777,size=128m");

    mkdir("run", 0755);
    mount("tmpfs", "run", "tmpfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, "mode=0755,size=64m");
}

/* Join cgroup */
static void join_cgroup(const char *cgroup_path) {
    if (!cgroup_path) return;

    char procs_file[PATH_MAX];
    snprintf(procs_file, sizeof(procs_file), "%s/cgroup.procs", cgroup_path);

    int fd = open(procs_file, O_WRONLY);
    if (fd < 0) DIE("open cgroup.procs");

    char pid_str[32];
    snprintf(pid_str, sizeof(pid_str), "%d", getpid());

    if (write(fd, pid_str, strlen(pid_str)) < 0) DIE("write to cgroup.procs");
    close(fd);
}

/* Set resource limits (DoS protection) */
static void set_ulimits(void) {
    struct rlimit rl;

    /* Max open files (prevent fd exhaustion) */
    rl.rlim_cur = rl.rlim_max = 1024;
    if (setrlimit(RLIMIT_NOFILE, &rl) < 0) {
        perror("setrlimit NOFILE");
    }

    /* Max processes (prevent fork spam, layer on cgroups) */
    rl.rlim_cur = rl.rlim_max = 256;
    if (setrlimit(RLIMIT_NPROC, &rl) < 0) {
        perror("setrlimit NPROC");
    }

    /* Max file size (prevent disk DoS) */
    rl.rlim_cur = rl.rlim_max = 100 * 1024 * 1024;  /* 100MB */
    if (setrlimit(RLIMIT_FSIZE, &rl) < 0) {
        perror("setrlimit FSIZE");
    }

    /* Disable core dumps */
    rl.rlim_cur = rl.rlim_max = 0;
    if (setrlimit(RLIMIT_CORE, &rl) < 0) {
        perror("setrlimit CORE");
    }
}

/* Async-safe int → string conversion for signal handler */
static void utoa(unsigned int val, char *buf, int *len) {
    if (val == 0) {
        buf[0] = '0';
        *len = 1;
        return;
    }

    char tmp[16];
    int j = 0;
    unsigned int v = val;
    while (v > 0) {
        tmp[j++] = '0' + (v % 10);
        v /= 10;
    }

    int i = 0;
    while (j > 0) {
        buf[i++] = tmp[--j];
    }
    *len = i;
}

/* Signal handler for seccomp violations (SIGSYS) */
static void sigsys_handler(int sig __attribute__((unused)), siginfo_t *info, void *ucontext __attribute__((unused))) {
    const char *prefix = "[SECCOMP] Blocked syscall: ";
    int prefix_len = sizeof("[SECCOMP] Blocked syscall: ") - 1;

    write(STDERR_FILENO, prefix, prefix_len);

    /* Defensive: check info validity (kernel hardening mindset) */
    if (info && info->si_syscall > 0) {
        char buf[16];
        int len;
        utoa(info->si_syscall, buf, &len);
        write(STDERR_FILENO, buf, len);
    } else {
        write(STDERR_FILENO, "unknown", 7);
    }

    write(STDERR_FILENO, "\n", 1);
    _exit(159);  /* _exit, not exit() — exit() is NOT async-safe */
}

/* Load seccomp BPF filter (strict allowlist, default KILL_PROCESS) */
static void load_seccomp(void) {
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &sd_seccomp_prog) < 0) {
        DIE("prctl(PR_SET_SECCOMP)");
    }
    /* Seccomp loaded. If process dies with signal 31 (SIGSYS), a syscall was blocked. */
}

int main(int argc, char *argv[], char *envp[]) {
    /* Handle --version flag for install.sh verification */
    if (argc > 1 && strcmp(argv[1], "--version") == 0) {
        write(STDOUT_FILENO, SD_INIT_VERSION, sizeof(SD_INIT_VERSION) - 1);
        write(STDOUT_FILENO, "\n", 1);
        _exit(0);
    }

    sd_init_config cfg = parse_args(argc, argv);

    /* 1. Close extra FDs */
    close_extra_fds();

    /* 2. Unshare namespaces */
    if (unshare(CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS | CLONE_NEWIPC | CLONE_NEWNET | CLONE_NEWUSER) < 0) {
        DIE("unshare");
    }

    /* 2.5. Register SIGSYS handler for seccomp violation logging */
    struct sigaction sa;
    sa.sa_sigaction = sigsys_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;
    if (sigaction(SIGSYS, &sa, NULL) < 0) {
        perror("sigaction SIGSYS");
        /* Non-fatal: continue without handler (seccomp will still kill process) */
    }

    /* 2.6. Register signal handlers for PID 1 init (forward to child, reap zombies) */
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = forward_signal;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGQUIT, &sa, NULL);

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = reap_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGCHLD, &sa, NULL);

    /* 3. Map UID/GID (root inside → calling user outside) */
    /* Simplified: map 0:0 inside to 0:0 outside (can be extended for non-root) */
    int uid_map = open("/proc/self/uid_map", O_WRONLY);
    if (uid_map < 0) DIE("open uid_map");
    if (write(uid_map, "0 0 65536\n", 10) < 0) DIE("write uid_map");
    close(uid_map);

    int gid_map = open("/proc/self/gid_map", O_WRONLY);
    if (gid_map < 0) DIE("open gid_map");
    if (write(gid_map, "0 0 65536\n", 10) < 0) DIE("write gid_map");
    close(gid_map);

    /* 4. Make all mounts private */
    if (mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL) < 0) {
        DIE("mount(MS_REC | MS_PRIVATE)");
    }

    /* 5. Bind-mount rootfs onto itself */
    if (mount(cfg.rootfs, cfg.rootfs, NULL, MS_BIND | MS_REC, NULL) < 0) {
        DIE("mount(MS_BIND)");
    }

    /* 6. Change directory into rootfs */
    if (chdir(cfg.rootfs) < 0) DIE("chdir");

    /* 7. Setup minimal /dev */
    setup_dev();

    /* 8. Setup /proc, /sys, /dev/pts, /dev/shm */
    setup_proc();
    mask_proc_paths();  /* Mask /proc/sys, /proc/irq, /proc/bus */
    setup_sys();
    setup_devpts_shm();

    /* 9. Setup /tmp and /run */
    setup_tmp_run();

    /* 10. Mask sensitive paths */
    mask_paths();

    /* 11. pivot_root */
    mkdir("old_root", 0700);
    if (pivot_root(".", "old_root") < 0) DIE("pivot_root");
    if (chdir("/") < 0) DIE("chdir /");
    if (umount2("/old_root", MNT_DETACH) < 0) DIE("umount2");
    if (rmdir("/old_root") < 0) DIE("rmdir");

    /* 12. Join cgroup BEFORE any user code runs */
    join_cgroup(cfg.cgroup_path);

    /* 13. Set no_new_privs */
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        DIE("prctl(PR_SET_NO_NEW_PRIVS)");
    }

    /* 14. Set resource limits */
    set_ulimits();

    /* 15. Load seccomp BPF filter */
    load_seccomp();

    /* 15. Drop all capabilities except allowed set */
    if (cfg.caps_count > 0) {
        drop_caps_except((const char**)cfg.caps, cfg.caps_count);
    } else {
        /* Drop all if no explicit caps requested */
        for (int cap = 0; cap <= CAP_LAST_CAP; cap++) {
            prctl(PR_CAPBSET_DROP, cap, 0, 0, 0);
        }
    }

    /* 16. Build environment from --env args or inherit */
    char **final_env = (char**)envp;
    if (cfg.env_count > 0) {
        final_env = malloc((cfg.env_count + 1) * sizeof(char*));
        for (int i = 0; i < cfg.env_count; i++) {
            final_env[i] = cfg.env[i];
        }
        final_env[cfg.env_count] = NULL;
    }

    /* 17. Fork child process (PID 1 init model) */
    pid_t pid = fork();
    if (pid < 0) {
        DIE("fork");
    }

    if (pid == 0) {
        /* Child process: execute user command */
        execve(cfg.cmd[0], cfg.cmd, final_env);
        DIE("execve");
    }

    /* Parent (PID 1): store child PID and wait for it */
    child_pid = pid;

    int status = 0;
    pid_t exited_pid = 0;

    /* Main loop: wait for main child to exit */
    while (1) {
        exited_pid = waitpid(child_pid, &status, 0);
        if (exited_pid == child_pid) {
            /* Main child exited */
            break;
        }
        /* If interrupted by signal, waitpid() returns -1 with errno=EINTR; retry */
        if (exited_pid < 0 && errno == EINTR) {
            continue;
        }
        /* Unexpected error (shouldn't happen) */
        if (exited_pid < 0) {
            break;
        }
    }

    /* Reap any remaining zombie children (children of the child process) */
    while (waitpid(-1, &status, WNOHANG) > 0) {
        /* Zombie reaped */
    }

    /* Exit with child's exit status */
    if (WIFEXITED(status)) {
        exit(WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
        /* Child died from signal: propagate it */
        raise(WTERMSIG(status));
    }

    exit(1);
}
