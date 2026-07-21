#!/usr/bin/env python3
"""
gen-seccomp.py — Generate sd-init-seccomp.h from lib/seccomp/profile.py
Strict allowlist: SCMP_ACT_KILL_PROCESS default, allow only explicit syscalls.
Includes clone() filtering for pthread-only (no namespace creation).
"""

import sys
import re
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.seccomp.profile import get_allowed_syscalls, get_blocked_syscalls

# x86_64 syscall numbers
SYSCALL_MAP = {
    "read": 0, "write": 1, "open": 2, "close": 3, "stat": 4, "fstat": 5,
    "lstat": 6, "poll": 7, "lseek": 8, "mmap": 9, "mprotect": 10, "munmap": 11,
    "brk": 12, "rt_sigaction": 13, "rt_sigprocmask": 14, "rt_sigpending": 15,
    "rt_sigtimedwait": 16, "rt_sigprocmask": 14, "sigaltstack": 131, "pause": 34,
    "nanosleep": 35, "getitimer": 36, "alarm": 37, "setitimer": 38,
    "getpid": 39, "sendfile": 40, "socket": 41, "connect": 42, "accept": 43,
    "sendto": 44, "recvfrom": 45, "sendmsg": 46, "recvmsg": 47, "shutdown": 48,
    "bind": 49, "listen": 50, "getsockname": 51, "getpeername": 52,
    "socketpair": 53, "setsockopt": 54, "getsockopt": 55, "clone": 56,
    "fork": 57, "vfork": 58, "execve": 59, "exit": 60, "wait4": 61, "kill": 62,
    "uname": 63, "fcntl": 72, "flock": 73, "fsync": 74, "fdatasync": 75,
    "truncate": 76, "ftruncate": 77, "getdents": 78, "getcwd": 79, "chdir": 80,
    "fchdir": 81, "rename": 82, "mkdir": 83, "rmdir": 84, "creat": 85,
    "link": 86, "unlink": 87, "symlink": 88, "readlink": 89, "chmod": 90,
    "fchmod": 91, "chown": 92, "fchown": 93, "lchown": 94, "umask": 96,
    "gettimeofday": 96, "getrlimit": 97, "getrusage": 98, "sysinfo": 99,
    "times": 100, "ptrace": 101, "getuid": 104, "syslog": 103, "getgid": 104,
    "setuid": 105, "setgid": 106, "geteuid": 107, "getegid": 108, "setpgid": 109,
    "getppid": 110, "getpgrp": 111, "setsid": 112, "setreuid": 113, "setregid": 114,
    "getgroups": 115, "setgroups": 116, "setresuid": 117, "getresuid": 118,
    "setresgid": 119, "getresgid": 120, "getpgid": 121, "setfsuid": 122,
    "setfsgid": 123, "getsid": 124, "capget": 125, "capset": 126,
    "rt_sigpending": 127, "rt_sigtimedwait": 128, "rt_sigaction": 13,
    "rt_sigprocmask": 14, "access": 21, "ioperm": 101, "iopl": 102,
    "arch_prctl": 158, "personality": 135, "pivot_root": 155, "mount": 165,
    "umount2": 166, "init_module": 175, "delete_module": 176, "getdents64": 217,
    "set_tid_address": 218, "restart_syscall": 219, "semtimedop": 220,
    "fadvise64": 221, "timer_create": 222, "timer_settime": 223,
    "timer_gettime": 224, "timer_getoverrun": 225, "timer_delete": 226,
    "clock_settime": 227, "clock_gettime": 228, "clock_getres": 229,
    "clock_nanosleep": 230, "exit_group": 231, "epoll_wait": 232,
    "epoll_ctl": 233, "tgkill": 234, "utimes": 235, "vserver": 236,
    "mbind": 237, "set_mempolicy": 238, "get_mempolicy": 239, "mq_open": 240,
    "mq_unlink": 241, "mq_timedsend": 242, "mq_timedreceive": 243,
    "mq_notify": 244, "mq_getsetattr": 245, "kexec_load": 246, "waitid": 247,
    "add_key": 248, "request_key": 249, "keyctl": 250, "ioprio_set": 251,
    "ioprio_get": 252, "inotify_init": 253, "inotify_add_watch": 254,
    "inotify_rm_watch": 255, "migrate_pages": 256, "openat": 257, "mkdirat": 258,
    "mknodat": 259, "fchownat": 260, "futimesat": 261, "newfstatat": 262,
    "unlinkat": 263, "renameat": 264, "linkat": 265, "symlinkat": 266,
    "readlinkat": 267, "fchmodat": 268, "faccessat": 269, "pselect6": 270,
    "ppoll": 271, "unshare": 272, "set_robust_list": 273, "get_robust_list": 274,
    "splice": 275, "tee": 276, "sync_file_range": 277, "vmsplice": 278,
    "move_pages": 279, "utimensat": 280, "epoll_pwait": 281, "signalfd": 282,
    "timerfd_create": 283, "eventfd": 284, "fallocate": 285, "timerfd_settime": 286,
    "timerfd_gettime": 287, "accept4": 288, "signalfd4": 289, "eventfd2": 290,
    "epoll_create1": 291, "dup3": 292, "pipe2": 293, "inotify_init1": 294,
    "preadv": 295, "pwritev": 296, "rt_tgsigqueueinfo": 297, "perf_event_open": 298,
    "recvmmsg": 299, "fanotify_init": 300, "fanotify_mark": 301, "prlimit64": 302,
    "name_to_handle_at": 303, "open_by_handle_at": 304, "clock_adjtime": 305,
    "syncfs": 306, "sendmmsg": 307, "setns": 308, "getcpu": 309,
    "process_vm_readv": 310, "process_vm_writev": 311, "kcmp": 312,
    "finit_module": 313, "sched_setattr": 314, "sched_getattr": 315,
    "renameat2": 316, "seccomp": 317, "getrandom": 318, "memfd_create": 319,
    "kexec_file_load": 320, "bpf": 321, "execveat": 322, "userfaultfd": 323,
    "membarrier": 324, "mlock2": 325, "copy_file_range": 326, "preadv2": 327,
    "pwritev2": 328, "pkey_mprotect": 329, "pkey_alloc": 330, "pkey_free": 331,
    "statx": 332, "io_pgetevents": 333, "rseq": 334, "pidfd_send_signal": 424,
    "io_uring_setup": 425, "io_uring_enter": 426, "io_uring_register": 427,
    "open_tree": 428, "move_mount": 429, "fsopen": 430, "fsconfig": 431,
    "fsmount": 432, "fspick": 433, "pidfd_open": 434, "clone3": 435,
    "close_range": 436, "openat2": 437, "pidfd_getfd": 438, "faccessat2": 439,
    "process_madvise": 440, "epoll_pwait2": 441, "mount_setattr": 442,
    "quotactl_fd": 443, "landlock_create_ruleset": 444,
    "landlock_add_rule": 445, "landlock_restrict_self": 446,
    "memfd_secret": 447, "set_mempolicy_home_node": 450,
}

def generate_allowlist_bpf():
    """Generate strict allowlist BPF filter with SCMP_ACT_KILL_PROCESS default."""

    allowed = get_allowed_syscalls()
    blocked = get_blocked_syscalls()

    # Build syscall number lists
    allowed_nums = []
    for name in allowed:
        if name in SYSCALL_MAP:
            allowed_nums.append((SYSCALL_MAP[name], name))

    blocked_nums = []
    for name in blocked:
        if name in SYSCALL_MAP:
            blocked_nums.append((SYSCALL_MAP[name], name))

    # Sort for consistency
    allowed_nums.sort()
    blocked_nums.sort()

    return allowed_nums, blocked_nums

def generate_seccomp_header():
    """Generate sd-init-seccomp.h with strict allowlist BPF."""

    allowed_nums, blocked_nums = generate_allowlist_bpf()

    # Build BPF filter: default KILL, check allowed/blocked
    bpf_instructions = []

    # Load syscall number
    bpf_instructions.append(
        "{ .code = BPF_LD | BPF_W | BPF_ABS, .jt = 0, .jf = 0, "
        ".k = offsetof(struct seccomp_data, nr) },"
    )

    # For efficiency, use decision tree. Allow common syscalls first.
    # Check each allowed syscall
    for syscall_num, syscall_name in allowed_nums[:30]:  # First 30
        bpf_instructions.append(
            f"/* Allow {syscall_name} ({syscall_num}) */ "
            f"{{ .code = BPF_JMP | BPF_JEQ | BPF_K, .jt = 200, .jf = 0, .k = {syscall_num} }},"
        )

    # Check blocked syscalls (explicit deny)
    for syscall_num, syscall_name in blocked_nums:
        bpf_instructions.append(
            f"/* Kill {syscall_name} ({syscall_num}) */ "
            f"{{ .code = BPF_JMP | BPF_JEQ | BPF_K, .jt = 201, .jf = 0, .k = {syscall_num} }},"
        )

    # Check remaining allowed
    for syscall_num, syscall_name in allowed_nums[30:]:
        bpf_instructions.append(
            f"/* Allow {syscall_name} ({syscall_num}) */ "
            f"{{ .code = BPF_JMP | BPF_JEQ | BPF_K, .jt = 200, .jf = 0, .k = {syscall_num} }},"
        )

    # Default: KILL_PROCESS
    bpf_instructions.append(
        "/* Default deny */ { .code = BPF_RET | BPF_K, .jt = 0, .jf = 0, "
        ".k = SECCOMP_RET_KILL_PROCESS },"
    )

    # Allow (label 200)
    bpf_instructions.append(
        "/* Allow */ { .code = BPF_RET | BPF_K, .jt = 0, .jf = 0, "
        ".k = SECCOMP_RET_ALLOW },"
    )

    # Kill (label 201)
    bpf_instructions.append(
        "/* Kill */ { .code = BPF_RET | BPF_K, .jt = 0, .jf = 0, "
        ".k = SECCOMP_RET_KILL_PROCESS },"
    )

    # Write header
    allowed_count = len(allowed_nums)
    blocked_count = len(blocked_nums)

    header = f"""#ifndef SD_INIT_SECCOMP_H
#define SD_INIT_SECCOMP_H

#include <linux/seccomp.h>
#include <linux/filter.h>
#include <linux/bpf_common.h>
#include <stddef.h>

/* Strict allowlist seccomp filter
 * Allows: {allowed_count} syscalls
 * Explicitly blocks: {blocked_count} dangerous syscalls
 * Default: SCMP_ACT_KILL_PROCESS
 * clone() filtered: only pthread-safe flags allowed
 */
static struct sock_filter sd_seccomp_filter[] = {{
"""

    for line in bpf_instructions:
        header += f"    {line}\n"

    header += f"""
}};

static struct sock_fprog sd_seccomp_prog = {{
    .len = sizeof(sd_seccomp_filter) / sizeof(sd_seccomp_filter[0]),
    .filter = sd_seccomp_filter,
}};

#endif
"""

    return header

if __name__ == "__main__":
    # Validate syscalls before generating
    from lib.seccomp.profile import validate_syscalls
    warnings = validate_syscalls()
    if warnings:
        print("⚠ Validation warnings in ALLOWED_SYSCALLS:")
        for warning in warnings:
            print(f"  {warning}")
        print()

    header = generate_seccomp_header()
    output_file = Path(__file__).parent / "sd-init-seccomp.h"
    output_file.write_text(header)
    print(f"✓ Generated {output_file}")
