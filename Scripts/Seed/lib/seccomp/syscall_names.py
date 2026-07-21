"""
lib/seccomp/syscall_names.py — Syscall number to name mapping (arch-aware)
Supports: x86_64, arm64, armv7, i386
"""

import platform

# x86_64 syscall mapping
X86_64_SYSCALLS = {
    0: "read", 1: "write", 2: "open", 3: "close", 4: "stat", 5: "fstat",
    6: "lstat", 7: "poll", 8: "lseek", 9: "mmap", 10: "mprotect",
    11: "munmap", 12: "brk", 13: "rt_sigaction", 14: "rt_sigprocmask",
    15: "rt_sigpending", 16: "rt_sigtimedwait", 17: "rt_sigqueueinfo",
    18: "rt_sigreturn", 19: "ioctl", 20: "pread64", 21: "pwrite64",
    22: "readv", 23: "writev", 24: "access", 25: "pipe", 26: "select",
    27: "sched_yield", 28: "mremap", 29: "msync", 30: "mincore",
    31: "madvise", 32: "shmget", 33: "shmat", 34: "shmctl", 35: "dup",
    36: "dup2", 37: "pause", 38: "nanosleep", 39: "getitimer", 40: "alarm",
    41: "setitimer", 42: "getpid", 43: "sendfile", 44: "socket", 45: "connect",
    46: "accept", 47: "sendto", 48: "recvfrom", 49: "sendmsg", 50: "recvmsg",
    51: "shutdown", 52: "bind", 53: "listen", 54: "getsockname", 55: "getpeername",
    56: "socketpair", 57: "setsockopt", 58: "getsockopt", 59: "clone", 60: "fork",
    61: "vfork", 62: "execve", 63: "exit", 64: "wait4", 65: "kill", 66: "uname",
    67: "fcntl", 68: "flock", 69: "fsync", 70: "fdatasync", 71: "truncate",
    72: "ftruncate", 73: "getdents", 74: "getcwd", 75: "chdir", 76: "fchdir",
    77: "rename", 78: "mkdir", 79: "rmdir", 80: "creat", 81: "link", 82: "unlink",
    83: "symlink", 84: "readlink", 85: "chmod", 86: "fchmod", 87: "chown",
    88: "fchown", 89: "lchown", 90: "umask", 91: "gettimeofday", 92: "getrlimit",
    93: "getrusage", 94: "sysinfo", 95: "times", 96: "ptrace", 97: "getuid",
    98: "syslog", 99: "getgid", 100: "setuid", 101: "setgid", 102: "geteuid",
    103: "getegid", 104: "setpgid", 105: "getppid", 106: "getpgrp", 107: "setsid",
    108: "setreuid", 109: "setregid", 110: "getgroups", 111: "setgroups",
    112: "setresuid", 113: "getresuid", 114: "setresgid", 115: "getresgid",
    116: "getpgid", 117: "setfsuid", 118: "setfsgid", 119: "getsid", 120: "capget",
    121: "capset", 122: "rt_pending", 123: "rt_sigpending", 124: "rt_sigtimedwait",
    125: "rt_sigqueueinfo", 126: "rt_sigsuspend", 127: "sigaltstack", 128: "utime",
    129: "mknod", 130: "uselib", 131: "personality", 132: "ustat", 133: "statfs",
    134: "fstatfs", 135: "sysfs", 136: "getpriority", 137: "setpriority",
    138: "sched_setparam", 139: "sched_getparam", 140: "sched_setscheduler",
    141: "sched_getscheduler", 142: "sched_get_priority_max", 143: "sched_get_priority_min",
    144: "sched_rr_get_interval", 145: "mlock", 146: "munlock", 147: "mlockall",
    148: "munlockall", 149: "vhangup", 150: "modify_ldt", 151: "_syscall",
    152: "arch_prctl", 153: "adjtimex", 154: "setrlimit", 155: "chroot",
    156: "sync", 157: "acct", 158: "settimeofday", 159: "mount", 160: "umount2",
    161: "syslog", 162: "uname", 163: "fdatasync", 164: "ftruncate64",
    165: "vserver", 166: "pread64", 167: "pwrite64", 168: "getdents64",
    169: "getcwd", 170: "readahead", 171: "setxattr", 172: "lsetxattr",
    173: "fsetxattr", 174: "getxattr", 175: "lgetxattr", 176: "fgetxattr",
    177: "listxattr", 178: "llistxattr", 179: "flistxattr", 180: "removexattr",
    181: "lremovexattr", 182: "fremovexattr", 183: "tkill", 184: "time",
    185: "futex", 186: "sched_setaffinity", 187: "sched_getaffinity",
    188: "set_thread_area", 189: "io_setup", 190: "io_destroy", 191: "io_getevents",
    192: "io_submit", 193: "io_cancel", 194: "get_thread_area", 195: "lookup_dcookie",
    196: "epoll_create", 197: "epoll_ctl_old", 198: "epoll_wait_old",
    199: "remap_file_pages", 200: "getdents64", 201: "set_tid_address",
    202: "restart_syscall", 203: "semtimedop", 204: "fadvise64", 205: "timer_create",
    206: "timer_settime", 207: "timer_gettime", 208: "timer_getoverrun",
    209: "timer_delete", 210: "clock_settime", 211: "clock_gettime",
    212: "clock_getres", 213: "clock_nanosleep", 214: "exit_group", 215: "epoll_wait",
    216: "epoll_ctl", 217: "tgkill", 218: "utimes", 219: "vserver", 220: "mbind",
    221: "set_mempolicy", 222: "get_mempolicy", 223: "mq_open", 224: "mq_unlink",
    225: "mq_timedsend", 226: "mq_timedreceive", 227: "mq_notify", 228: "mq_getsetattr",
    229: "kexec_load", 230: "waitid", 231: "add_key", 232: "request_key",
    233: "keyctl", 234: "ioprio_set", 235: "ioprio_get", 236: "inotify_init",
    237: "inotify_add_watch", 238: "inotify_rm_watch", 239: "migrate_pages",
    240: "openat", 241: "mkdirat", 242: "mknodat", 243: "fchownat", 244: "futimesat",
    245: "newfstatat", 246: "unlinkat", 247: "renameat", 248: "linkat", 249: "symlinkat",
    250: "readlinkat", 251: "fchmodat", 252: "faccessat", 253: "pselect6",
    254: "ppoll", 255: "unshare", 256: "set_robust_list", 257: "get_robust_list",
    258: "splice", 259: "tee", 260: "sync_file_range", 261: "vmsplice", 262: "move_pages",
    263: "utimensat", 264: "epoll_pwait", 265: "signalfd", 266: "timerfd_create",
    267: "eventfd", 268: "fallocate", 269: "timerfd_settime", 270: "timerfd_gettime",
    271: "accept4", 272: "signalfd4", 273: "eventfd2", 274: "epoll_create1",
    275: "dup3", 276: "pipe2", 277: "inotify_init1", 278: "preadv", 279: "pwritev",
    280: "rt_tgsigqueueinfo", 281: "perf_event_open", 282: "recvmmsg", 283: "fanotify_init",
    284: "fanotify_mark", 285: "prlimit64", 286: "name_to_handle_at", 287: "open_by_handle_at",
    288: "clock_adjtime", 289: "syncfs", 290: "sendmmsg", 291: "setns", 292: "getcpu",
    293: "process_vm_readv", 294: "process_vm_writev", 295: "kcmp", 296: "finit_module",
    297: "sched_setattr", 298: "sched_getattr", 299: "renameat2", 300: "seccomp",
    301: "getrandom", 302: "memfd_create", 303: "kexec_file_load", 304: "bpf",
    305: "execveat", 306: "userfaultfd", 307: "membarrier", 308: "mlock2",
    309: "copy_file_range", 310: "preadv2", 311: "pwritev2", 312: "pkey_mprotect",
    313: "pkey_alloc", 314: "pkey_free",
}

# ARM64 (aarch64) syscall mapping
ARM64_SYSCALLS = {
    0: "io_setup", 1: "io_destroy", 2: "io_submit", 3: "io_cancel", 4: "io_getevents",
    5: "setxattr", 6: "lsetxattr", 7: "fsetxattr", 8: "getxattr", 9: "lgetxattr",
    10: "fgetxattr", 11: "listxattr", 12: "llistxattr", 13: "flistxattr",
    14: "removexattr", 15: "lremovexattr", 16: "fremovexattr", 17: "getcwd",
    18: "lookup_dcookie", 19: "eventfd", 20: "epoll_create1", 21: "epoll_ctl",
    22: "epoll_wait", 23: "dup", 24: "dup3", 25: "fcntl", 26: "inotify_init1",
    27: "inotify_add_watch", 28: "inotify_rm_watch", 29: "ioctl", 30: "ioprio_set",
    31: "ioprio_get", 32: "flock", 33: "mknodat", 34: "mkdirat", 35: "unlinkat",
    36: "symlinkat", 37: "linkat", 38: "renameat", 39: "umask", 40: "truncate",
    41: "ftruncate", 42: "fallocate", 43: "faccessat", 44: "chdir", 45: "fchdir",
    46: "chroot", 47: "fchmod", 48: "fchmodat", 49: "fchownat", 50: "fchown",
    51: "lchown", 52: "fchown", 53: "fstat", 54: "statx", 55: "stat", 56: "lstat",
    57: "newfstatat", 58: "statfs", 59: "fstatfs", 60: "lseek", 61: "mmap",
    62: "mprotect", 63: "munmap", 64: "brk", 65: "mremap", 66: "madvise",
    67: "remap_file_pages", 68: "mbind", 69: "get_mempolicy", 70: "set_mempolicy",
    71: "migrate_pages", 72: "move_pages", 73: "mlock", 74: "mlockall",
    75: "munlock", 76: "munlockall", 77: "mlock2", 78: "munlock", 79: "munlockall",
    80: "madvise", 81: "mincore", 82: "msyncs", 83: "madvise", 84: "mremap",
    85: "mmap", 86: "mprotect", 87: "munmap", 88: "brk", 89: "mmap2",
    90: "mmap", 91: "pread64", 92: "pwrite64", 93: "readv", 94: "writev",
    95: "preadv", 96: "pwritev", 97: "access", 98: "pipe", 99: "select",
    100: "sched_yield", 101: "mremap", 102: "msync", 103: "mincore",
    104: "madvise", 105: "shmget", 106: "shmat", 107: "shmctl", 108: "dup",
    109: "dup2", 110: "pause", 111: "nanosleep", 112: "getitimer", 113: "alarm",
    114: "setitimer", 115: "getpid", 116: "sendfile", 117: "socketpair",
    118: "socket", 119: "bind", 120: "connect", 121: "listen", 122: "accept",
    123: "getsockname", 124: "getpeername", 125: "socketpair", 126: "setsockopt",
    127: "getsockopt", 128: "shutdown", 129: "sendto", 130: "send", 131: "recvfrom",
    132: "recv", 133: "setsockopt", 134: "getsockopt", 135: "shutdown", 136: "sendmsg",
    137: "recvmsg", 138: "sendto", 139: "recvfrom", 140: "setsockopt",
    141: "getsockopt", 142: "shutdown", 143: "sendmsg", 144: "recvmsg",
    145: "truncate", 146: "ftruncate", 147: "stat", 148: "fstat", 149: "fstatx",
    150: "lstat", 151: "poll", 152: "ppoll", 153: "prctl", 154: "rt_sigreturn",
    155: "rt_sigaction", 156: "rt_sigprocmask", 157: "rt_sigpending",
    158: "rt_sigtimedwait", 159: "rt_sigqueueinfo", 160: "rt_sigsuspend",
    161: "sigaltstack", 162: "kill", 163: "tgkill", 164: "tkill", 165: "rt_sigpending",
    166: "futex", 167: "sched_setparam", 168: "sched_setscheduler",
    169: "sched_getscheduler", 170: "sched_getparam", 171: "sched_get_priority_max",
    172: "sched_get_priority_min", 173: "sched_rr_get_interval", 174: "mlock",
    175: "munlock", 176: "mlockall", 177: "munlockall", 178: "vhangup",
    179: "modify_ldt", 180: "_syscall", 181: "arch_prctl", 182: "adjtimex",
    183: "setrlimit", 184: "chroot", 185: "sync", 186: "acct", 187: "settimeofday",
    188: "mount", 189: "umount2", 190: "syslog", 191: "uname", 192: "fdatasync",
    193: "ftruncate64", 194: "fstat", 195: "fcntl", 196: "flock", 197: "fsync",
    198: "fdatasync", 199: "ftruncate", 200: "truncate", 201: "statfs",
    202: "fstatfs", 203: "sysfs", 204: "getpriority", 205: "setpriority",
    206: "sched_setparam", 207: "sched_getparam", 208: "sched_setscheduler",
    209: "sched_getscheduler", 210: "sched_get_priority_max", 211: "sched_get_priority_min",
    212: "sched_rr_get_interval", 213: "mlock", 214: "munlock", 215: "mlockall",
    216: "munlockall",
}

def get_syscall_map():
    """Get syscall mapping for current architecture."""
    machine = platform.machine()

    if machine == "x86_64":
        return X86_64_SYSCALLS
    elif machine in ("aarch64", "arm64"):
        return ARM64_SYSCALLS
    else:
        # Fallback to x86_64 (most common)
        return X86_64_SYSCALLS

def get_syscall_name(num):
    """Get syscall name by number (current arch). Kernel is source of truth."""
    syscalls = get_syscall_map()
    # Return name if found, fallback to unknown(num) format
    return syscalls.get(num, f"unknown({num})")

def get_syscall_number(name):
    """Get syscall number by name (reverse lookup, current arch)."""
    syscalls = get_syscall_map()
    for num, syscall_name in syscalls.items():
        if syscall_name == name:
            return num
    # Not found in current arch mapping
    return None

def is_known_syscall(name):
    """Check if syscall name is in current arch mapping."""
    return get_syscall_number(name) is not None

def get_current_arch():
    """Return current architecture."""
    return platform.machine()
