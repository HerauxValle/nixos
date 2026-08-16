// &desc: "Thin wrapper around libseccomp-sys applying a syscall filter for exec's sandbox. Syscall names are resolved to numbers by libseccomp itself, per the architecture cas is actually running on -- never a hardcoded numeric table, which is what makes this portable across CPU architectures without cas having to know or maintain per-arch syscall number tables. Kept behind this one small file so swapping the underlying implementation later (e.g. a hand-rolled BPF builder) is a contained change, not a rewrite."
use std::ffi::CString;
use std::io;

/// Mirrors `registry::seccomp::Mode` -- this module intentionally
/// doesn't depend on `registry` (pure mechanism, no data-loading
/// concerns), so the caller translates.
pub enum Mode {
    /// `syscalls` are blocked; everything else is allowed.
    Denylist,
    /// Only `syscalls` are allowed; everything else is blocked.
    Allowlist,
}

/// Applies a filter to the *calling* process, inherited by every
/// process it forks/execs afterward -- called once, from `mod.rs::run`,
/// at the same point `harden::apply` runs (before the required fork
/// into the PID1 child), so both PID1 and the eventual foreground
/// command are covered. `syscalls` are resolved for the host's actual
/// running architecture; a name libseccomp doesn't recognize is skipped
/// rather than treated as fatal (some syscalls genuinely don't exist on
/// every architecture/kernel combination).
pub fn apply(mode: Mode, syscalls: &[String]) -> io::Result<()> {
    let def_action = match mode {
        Mode::Denylist => libseccomp_sys::SCMP_ACT_ALLOW,
        Mode::Allowlist => libseccomp_sys::SCMP_ACT_ERRNO(libc::EPERM as u16),
    };
    let rule_action = match mode {
        Mode::Denylist => libseccomp_sys::SCMP_ACT_ERRNO(libc::EPERM as u16),
        Mode::Allowlist => libseccomp_sys::SCMP_ACT_ALLOW,
    };

    let ctx = unsafe { libseccomp_sys::seccomp_init(def_action) };
    if ctx.is_null() {
        return Err(io::Error::new(io::ErrorKind::Other, "seccomp_init failed"));
    }

    for name in syscalls {
        let Ok(cname) = CString::new(name.as_str()) else { continue };
        let nr = unsafe { libseccomp_sys::seccomp_syscall_resolve_name(cname.as_ptr()) };
        if nr == libseccomp_sys::__NR_SCMP_ERROR {
            continue; // unknown on this architecture/libseccomp version -- skip, not fatal
        }
        let ret = unsafe { libseccomp_sys::seccomp_rule_add(ctx, rule_action, nr, 0) };
        if ret != 0 {
            unsafe { libseccomp_sys::seccomp_release(ctx) };
            return Err(io::Error::from_raw_os_error(-ret));
        }
    }

    // `seccomp_load` installs the filter into the running kernel;
    // releasing the builder context afterward doesn't undo it.
    let ret = unsafe { libseccomp_sys::seccomp_load(ctx) };
    unsafe { libseccomp_sys::seccomp_release(ctx) };
    if ret != 0 {
        return Err(io::Error::from_raw_os_error(-ret));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Forks so the filter only ever applies to a throwaway child, not
    /// the test process itself -- runs entirely unprivileged, no
    /// namespace/mount involvement at all.
    fn run_in_child(f: impl FnOnce()) -> i32 {
        let pid = unsafe { libc::fork() };
        assert!(pid >= 0, "fork failed");
        if pid == 0 {
            f();
            unsafe { libc::_exit(0) };
        }
        let mut status: libc::c_int = 0;
        unsafe { libc::waitpid(pid, &mut status, 0) };
        if libc::WIFEXITED(status) {
            libc::WEXITSTATUS(status)
        } else {
            -1
        }
    }

    #[test]
    fn denylist_blocks_the_listed_syscall() {
        let code = run_in_child(|| {
            apply(Mode::Denylist, &["getcwd".to_string()]).expect("apply should succeed");
            let mut buf = [0i8; 64];
            let ret = unsafe { libc::getcwd(buf.as_mut_ptr(), buf.len()) };
            // Denylist's rule action is SCMP_ACT_ERRNO(EPERM): the
            // syscall itself must now fail, not merely warn.
            let errno = std::io::Error::last_os_error().raw_os_error();
            unsafe { libc::_exit(if ret.is_null() && errno == Some(libc::EPERM) { 0 } else { 1 }) };
        });
        assert_eq!(code, 0, "getcwd should have been blocked by the denylist");
    }

    #[test]
    fn allowlist_permits_only_the_listed_syscalls() {
        let code = run_in_child(|| {
            // Deliberately omit "write"/"exit_group" -- the allowlist
            // must still let the process's own controlled exit (via
            // _exit, an alias for exit_group) through, or this test
            // can never report its own result. Include just enough to
            // prove the filter is live at all: allow getpid, block
            // getcwd implicitly by omission.
            apply(Mode::Allowlist, &["getpid".to_string(), "exit_group".to_string(), "rt_sigreturn".to_string()]).expect("apply should succeed");
            let pid = unsafe { libc::getpid() };
            let mut buf = [0i8; 64];
            let ret = unsafe { libc::getcwd(buf.as_mut_ptr(), buf.len()) };
            let errno = std::io::Error::last_os_error().raw_os_error();
            let getpid_worked = pid > 0;
            let getcwd_blocked = ret.is_null() && errno == Some(libc::EPERM);
            unsafe { libc::_exit(if getpid_worked && getcwd_blocked { 0 } else { 1 }) };
        });
        assert_eq!(code, 0, "getpid should have worked (allowlisted) and getcwd should have been blocked (not allowlisted)");
    }
}
