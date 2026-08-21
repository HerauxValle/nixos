// &desc: "clone(2) with every requested namespace flag combined + /proc/self/uid_map,gid_map writing for exec's sandbox -- the unprivileged 'rootless container' trick: any user can create a user namespace, and inside it gets full capabilities, but only within that namespace. A single combined clone() (not unshare()+fork() as two separate steps) matters empirically here, not just stylistically -- see clone_into_namespaces's doc comment."
use std::ffi::CString;
use std::fs;
use std::io;
use std::mem;

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

/// Every requested namespace except user, in one `unshare(2)` call --
/// confirmed against a known-working reference (this project's own
/// `Scripts/Seed/helpers/sd-init.c`, a C container-init binary that
/// does the same combined `unshare(CLONE_NEWNS|NEWPID|NEWUTS|NEWIPC|
/// NEWNET)`, no `fork()` involved yet at this point). The earlier
/// "Mount too revealing" EPERM chased through several `unshare()`/
/// `fork()`/`clone()` orderings turned out not to be an ordering
/// problem at all -- see `mod.rs::run`'s doc comment for the real cause
/// (mounting `/proc` *after* `pivot_root` instead of before). User is
/// excluded here and unshared separately, later -- see `unshare_user`'s
/// doc comment for why the two are split and called in this specific
/// order.
pub fn unshare_without_user(flags: &Flags) -> io::Result<()> {
    let f = flags.to_libc() & !libc::CLONE_NEWUSER;
    let ret = unsafe { libc::unshare(f) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// `unshare(CLONE_NEWUSER)` alone, called *after* every host-mount
/// operation (overlay, bind-self, procfs, devfs, pivot_root) is already
/// done -- not combined into the same call as the other namespaces the
/// way an earlier version of this code did. Reason: `cas` always
/// self-elevates to real root before this ever runs (see
/// `mod.rs::run`'s doc comment), so there's no unprivileged-caller case
/// to support here -- the "rootless container trick" this module's own
/// top-of-file comment describes only applies to a genuinely
/// unprivileged caller. For real root, entering a new user namespace
/// *before* mounting anything is actively harmful, not just
/// unnecessary: a task's capabilities in a newly created child user
/// namespace do not extend to its parent (here, the real init user
/// namespace that owns the vault's own already-mounted filesystem) --
/// `cap_capable()` only grants capabilities *downward* into namespaces
/// you created, never back up into the one you came from. So a process
/// that unshares the user namespace first loses `CAP_SYS_ADMIN` over
/// every pre-existing host mount, including the vault's own mount
/// point -- confirmed empirically: both the overlay mount (needs
/// `trusted.*` xattr rights) and the plain self bind-mount that
/// `pivot_root` requires as its target both failed with
/// `EPERM`/`EACCES` when the user namespace was unshared up front. Real
/// root already has every capability the user-namespace trick exists to
/// grant unprivileged callers, so mounting is done first as plain real
/// root, and the user namespace is entered afterward -- right before
/// `harden::apply()` -- purely to contain the actual sandboxed command,
/// which never needs to touch a pre-pivot host mount at all.
pub fn unshare_user() -> io::Result<()> {
    let ret = unsafe { libc::unshare(libc::CLONE_NEWUSER) };
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

/// Brings `lo` up inside whatever network namespace is currently active
/// for the calling thread -- must be called *after* `unshare(CLONE_NEWNET)`
/// has already taken effect (i.e. after `unshare_without_user` when
/// `flags.net` was set), never before, or this configures the host's own
/// loopback instead of the new namespace's.
///
/// A fresh `CLONE_NEWNET` namespace starts with `lo` present but
/// administratively down and no routes -- without this, every loopback
/// connection (many programs' own health checks, localhost DNS resolvers,
/// anything binding `127.0.0.1`) fails outright even though the interface
/// exists. This does not provide any route *out* of the namespace (no
/// veth/NAT) -- an isolated `exec` session still can't reach the host's
/// real network or the internet, by design; it only makes the namespace's
/// own loopback usable rather than a completely dead stub.
///
/// Uses a raw `ioctl(SIOCGIFFLAGS/SIOCSIFFLAGS)` on a throwaway
/// `AF_INET`/`SOCK_DGRAM` socket -- the same mechanism `ip link set lo up`
/// itself ultimately uses, no netlink socket or external command needed.
pub fn bring_up_loopback() -> io::Result<()> {
    let sock = unsafe { libc::socket(libc::AF_INET, libc::SOCK_DGRAM, 0) };
    if sock < 0 {
        return Err(io::Error::last_os_error());
    }

    let mut ifr: libc::ifreq = unsafe { mem::zeroed() };
    let name = CString::new("lo").expect("static string has no interior NUL");
    let name_bytes = name.as_bytes_with_nul();
    for (dst, &src) in ifr.ifr_name.iter_mut().zip(name_bytes.iter()) {
        *dst = src as libc::c_char;
    }

    let result = (|| -> io::Result<()> {
        if unsafe { libc::ioctl(sock, libc::SIOCGIFFLAGS, &mut ifr) } != 0 {
            return Err(io::Error::last_os_error());
        }
        unsafe {
            ifr.ifr_ifru.ifru_flags |= libc::IFF_UP as libc::c_short;
        }
        if unsafe { libc::ioctl(sock, libc::SIOCSIFFLAGS, &ifr) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    })();

    unsafe { libc::close(sock) };
    result
}
