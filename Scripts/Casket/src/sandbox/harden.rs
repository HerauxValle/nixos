// &desc: "prctl hardening for exec's sandbox -- NO_NEW_PRIVS blocks privilege gain via a setuid binary or file capability sitting inside the rootfs; capability-bounding-set drops matter even inside a user namespace as real defense-in-depth against the kernel-bug class of container escape, not redundant with the namespace itself."
use std::io;



// The `libc` crate doesn't expose Linux capability numbers by name (no
// `libc::CAP_*` constants) -- these are the fixed values from
// <linux/capability.h>, stable across kernel versions since they're a
// public ABI.
const CAP_NET_ADMIN: libc::c_int = 12;
const CAP_SYS_MODULE: libc::c_int = 16;
const CAP_SYS_BOOT: libc::c_int = 22;
const CAP_SYS_TIME: libc::c_int = 25;

/// Capabilities dropped from the bounding set even though a user
/// namespace's fake root already can't use them against the real host
/// -- these are the ones that matter if a kernel bug ever lets a
/// namespace capability check pass when it shouldn't.
const DROP: &[libc::c_int] = &[CAP_SYS_MODULE, CAP_SYS_BOOT, CAP_SYS_TIME, CAP_NET_ADMIN];

pub fn apply() -> io::Result<()> {
    let ret = unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) };
    if ret != 0 {
        return Err(io::Error::last_os_error().into());
    }
    for cap in DROP {
        let ret = unsafe { libc::prctl(libc::PR_CAPBSET_DROP, *cap, 0, 0, 0) };
        if ret != 0 {
            return Err(io::Error::last_os_error().into());
        }
    }
    Ok(())
}
