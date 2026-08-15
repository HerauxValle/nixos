// &desc: "clone(2) with every requested namespace flag combined + /proc/self/uid_map,gid_map writing for exec's sandbox -- the unprivileged 'rootless container' trick: any user can create a user namespace, and inside it gets full capabilities, but only within that namespace. A single combined clone() (not unshare()+fork() as two separate steps) matters empirically here, not just stylistically -- see clone_into_namespaces's doc comment."
use std::fs;
use std::io;

/// Bit flags for the sandbox's namespaces, named the same as the CLI's
/// namespace list (`sandbox::namespaces::ALL`) so callers don't have to
/// hand-translate.
pub struct Flags {
    pub mount: bool,
    pub pid: bool,
    pub uts: bool,
    pub ipc: bool,
    pub user: bool,
    pub net: bool,
}

impl Flags {
    pub fn to_libc(&self) -> libc::c_int {
        let mut f = 0;
        if self.mount {
            f |= libc::CLONE_NEWNS;
        }
        if self.pid {
            f |= libc::CLONE_NEWPID;
        }
        if self.uts {
            f |= libc::CLONE_NEWUTS;
        }
        if self.ipc {
            f |= libc::CLONE_NEWIPC;
        }
        if self.user {
            f |= libc::CLONE_NEWUSER;
        }
        if self.net {
            f |= libc::CLONE_NEWNET;
        }
        f
    }
}

/// `unshare(2)` with every requested namespace flag combined into one
/// call -- confirmed against a known-working reference (this project's
/// own `Scripts/Seed/helpers/sd-init.c`, a C container-init binary that
/// does the same `unshare(CLONE_NEWNS|NEWPID|NEWUTS|NEWIPC|NEWNET|
/// NEWUSER)` as a single call, no `fork()` involved yet at this point).
/// It turned out the earlier "Mount too revealing" EPERM chased through
/// several `unshare()`/`fork()`/`clone()` orderings wasn't actually an
/// ordering problem at all -- see `mod.rs::run`'s doc comment for the
/// real cause (mounting `/proc` *after* `pivot_root` instead of before,
/// into the pre-pivot new-root path).
pub fn unshare(flags: &Flags) -> io::Result<()> {
    let ret = unsafe { libc::unshare(flags.to_libc()) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// Maps the real calling uid/gid to root (0) *inside* the new user
/// namespace -- root-inside is never real host root, it's the same
/// unprivileged user, just seeing themselves as uid 0 within their own
/// namespace. Called from inside the child (via `/proc/self/...`,
/// which now refers to the child's own, already-active user
/// namespace). `/proc/self/setgroups` must be written `deny` before
/// `gid_map`, or the kernel refuses the gid_map write outright -- the
/// one step in this whole sequence where getting the order wrong
/// produces a namespace that looks set up but silently isn't.
pub fn write_id_maps(real_uid: u32, real_gid: u32) -> io::Result<()> {
    fs::write("/proc/self/setgroups", b"deny")?;
    fs::write("/proc/self/uid_map", format!("0 {real_uid} 1"))?;
    fs::write("/proc/self/gid_map", format!("0 {real_gid} 1"))?;
    Ok(())
}
