"""
lib/seccomp/profile.py — Strict allowlist for container seccomp
Default deny, explicit allow for required syscalls only
"""

# Syscalls explicitly allowed in container
ALLOWED_SYSCALLS = {
    # Execution
    "execve", "execveat",

    # Process management
    "fork", "vfork", "clone", "exit", "exit_group", "getpid", "gettid",
    "getppid", "getpgrp", "getpgid", "setsid", "setpgid",

    # Signal handling
    "rt_sigaction", "rt_sigprocmask", "rt_sigpending", "rt_sigtimedwait",
    "sigaltstack", "pause", "kill", "tgkill", "rt_sigreturn",

    # File I/O (basic)
    "read", "write", "pread64", "pwrite64", "readv", "writev", "preadv", "pwritev",
    "dup", "dup2", "dup3", "close", "lseek",

    # File operations
    "openat", "open", "creat", "unlink", "unlinkat",
    "mkdir", "mkdirat", "rmdir", "link", "linkat", "symlink", "symlinkat",
    "readlink", "readlinkat", "rename", "renameat", "renameat2",

    # File info
    "stat", "lstat", "fstat", "fstatat", "statx", "getdents", "getdents64",
    "getcwd", "chdir", "fchdir",

    # File permissions
    "chmod", "fchmod", "fchmodat", "chown", "fchown", "fchownat", "lchown",
    "umask", "access", "faccessat",

    # Memory mapping
    "mmap", "mmap2", "munmap", "mprotect", "mremap", "madvise", "mlock", "munlock",
    "mlockall", "munlockall", "brk",

    # File locking
    "fcntl", "flock", "flock64",

    # Directory operations
    "fsync", "fdatasync", "ftruncate", "truncate", "ftruncate64", "truncate64",

    # Pipes and sockets
    "pipe", "pipe2", "socket", "socketpair", "bind", "connect", "accept",
    "accept4", "listen", "sendto", "recvfrom", "sendmsg", "recvmsg",
    "shutdown", "setsockopt", "getsockopt", "getsockname", "getpeername",

    # Timers and time
    "clock_gettime", "clock_gettime64", "clock_settime", "clock_settime64",
    "clock_nanosleep", "nanosleep", "getitimer", "setitimer", "alarm",
    "gettimeofday", "settimeofday", "adjtimex", "clock_adjtime",

    # Process resource limits
    "getrlimit", "setrlimit", "prlimit64",

    # Process information
    "getrusage", "getuid", "geteuid", "getgid", "getegid",
    "setuid", "setgid", "seteuid", "setegid", "setreuid", "setregid",
    "setresuid", "setresgid", "getresuid", "getresgid",
    "getgroups", "setgroups", "setfsuid", "setfsgid",

    # Capability management
    "capget", "capset",

    # System information
    "uname", "arch_prctl", "personality", "sysinfo",

    # Memory/virtual memory
    "page_size", "getrandom", "getentropy",

    # Threading (pthread-style allowed)
    "set_tid_address", "set_robust_list", "futex", "futex2", "futex_waitv",

    # Futex wakeup
    "futex_requeue",

    # Process tracing (disabled by seccomp anyway, but don't block ptrace for now)
    # ptrace is EXPLICITLY not in this list

    # Device I/O (ioctl allowed for tty/fs ops)
    "ioctl", "ioctl32",

    # Poll/select
    "poll", "ppoll", "select", "pselect6", "epoll_create", "epoll_create1",
    "epoll_ctl", "epoll_wait", "epoll_pwait", "epoll_pwait2",

    # Message queues (optional, add if needed)
    "mq_open", "mq_close", "mq_getsetattr", "mq_notify", "mq_send", "mq_receive",

    # Shared memory
    "shmget", "shmat", "shmctl", "shmdt",

    # IPC (semaphores, message queues)
    "msgget", "msgctl", "msgsnd", "msgrcv",
    "semget", "semctl", "semop", "semtimedop",

    # Memory advice (for performance optimization)
    "posix_madvise",

    # Signal delivery
    "pselect6",
}

# Syscalls explicitly BLOCKED (defense in depth)
BLOCKED_SYSCALLS = {
    # Namespace manipulation
    "unshare", "setns",

    # Mount operations (already blocked in kernel by pivot_root + immutable rootfs)
    "mount", "umount", "umount2", "pivot_root",

    # Kernel modules
    "init_module", "finit_module", "delete_module",

    # BPF
    "bpf",

    # Process tracing
    "ptrace", "process_vm_readv", "process_vm_writev",

    # Capability manipulation
    # (capset allowed but restricted by capabilities)

    # Raw sockets
    # (socket allowed, only specific families blocked in ioctl)

    # Kexec
    "kexec_load", "kexec_file_load",

    # Memory access (mmap allowed, but kernel enforces)
}

def get_allowed_syscalls() -> set[str]:
    """Return set of syscalls allowed in container (allowlist)."""
    return ALLOWED_SYSCALLS

def get_blocked_syscalls() -> set[str]:
    """Return set of syscalls explicitly blocked (defense in depth)."""
    return BLOCKED_SYSCALLS

def validate_syscalls() -> list[str]:
    """Validate ALLOWED_SYSCALLS for typos and unknown names. Returns warnings."""
    from lib.seccomp.syscall_names import is_known_syscall
    warnings = []

    for syscall in ALLOWED_SYSCALLS:
        if not is_known_syscall(syscall):
            warnings.append(f"⚠ Syscall '{syscall}' unknown on current architecture (possible typo?)")

    return warnings


def get_restricted_syscalls(spec) -> set[str]:
    """Return syscalls to restrict based on SecuritySpec.

    Implements seccomp + AppArmor synergy:
    If feature disabled in SecuritySpec, restrict related syscalls.

    For example, if network_enabled=False, restrict socket syscalls.
    This prevents the app from even trying to create sockets (defense in depth).

    Args:
        spec: SecuritySpec instance

    Returns:
        Set of syscall names to block (in addition to BLOCKED_SYSCALLS)
    """
    to_restrict = set()

    # Network isolation: if network disabled, block network syscalls
    if not spec.network_enabled:
        # Block socket creation and network operations
        network_syscalls = {
            "socket",       # Create socket
            "socketpair",   # Create socket pair
            "bind",         # Bind socket to address
            "connect",      # Connect to remote address
            "listen",       # Listen on socket
            "accept",       # Accept connection
            "accept4",      # Accept with flags
            "sendto",       # Send message to address
            "recvfrom",     # Receive from address
            "sendmsg",      # Send message
            "recvmsg",      # Receive message
            "setsockopt",   # Set socket options
            "getsockopt",   # Get socket options
            "shutdown",     # Shutdown socket
        }
        to_restrict.update(network_syscalls)

    # Note: /tmp access is handled by AppArmor filesystem rules, not seccomp.
    # Seccomp can't enforce path-based restrictions (requires full path lookup).
    # AppArmor denies open(/tmp) at filesystem level.

    return to_restrict
