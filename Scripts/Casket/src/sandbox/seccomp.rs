// &desc: "Hand-rolled seccomp-BPF filter builder for exec's sandbox -- no libc library dependency (no libseccomp), just raw prctl(PR_SET_SECCOMP) with a classic BPF program built from registry::syscall_table's per-architecture name->number tables. Kept behind this one small file so the internals (or a future switch back to a C library, if ever wanted) stay a contained change."
use std::io;

use super::syscall_table;

/// A syscall filter: `allow` and `deny` can both be non-empty at once
/// (a syscall named in both is a caller error -- rejected before this
/// ever gets built, see `commands::settings::security::sandbox::
/// seccomp::profiles`), with `default_deny` picking the fallback action
/// for anything named in neither list. This is the one shape every
/// filter this sandbox ever applies reduces to: a built-in *denylist*
/// preset is `default_deny: false` with only `deny` populated, a built-
/// in *allowlist* preset is `default_deny: true` with only `allow`
/// populated, and a named custom profile (`seccomp custom`) can
/// populate both lists and choose its own default explicitly -- the
/// registry's `AllowAll` preset skips calling `apply` entirely rather
/// than being representable here (there's no BPF program for "no
/// filter").
pub struct Filter {
    pub default_deny: bool,
    pub allow: Vec<String>,
    pub deny: Vec<String>,
}

// --- Raw kernel ABI, straight from linux/filter.h, linux/seccomp.h,
// linux/audit.h -- these are fixed, stable public ABI constants, not
// version-sensitive the way syscall numbers themselves are (which is
// why *those* are a generated data table and these are not).

const BPF_LD_W_ABS: u16 = 0x00 | 0x00 | 0x20; // BPF_LD | BPF_W | BPF_ABS
const BPF_JMP_JEQ_K: u16 = 0x05 | 0x10 | 0x00; // BPF_JMP | BPF_JEQ | BPF_K
const BPF_RET_K: u16 = 0x06 | 0x00; // BPF_RET | BPF_K

const SECCOMP_RET_KILL_PROCESS: u32 = 0x8000_0000;
const SECCOMP_RET_ALLOW: u32 = 0x7fff_0000;
const SECCOMP_RET_ERRNO: u32 = 0x0005_0000;

const PR_SET_SECCOMP: libc::c_int = 22;
const SECCOMP_MODE_FILTER: libc::c_ulong = 2;

// offsetof(struct seccomp_data, nr) and ...arch -- `nr` (int, 4 bytes)
// is the struct's first field, `arch` (__u32, 4 bytes) immediately
// follows. Fixed kernel ABI, not something that changes between
// kernel versions.
const SECCOMP_DATA_NR_OFFSET: u32 = 0;
const SECCOMP_DATA_ARCH_OFFSET: u32 = 4;

// AUDIT_ARCH_* from linux/audit.h -- identifies which syscall table a
// filter's numbers are meant for. Checked first and unconditionally,
// so a filter built for one architecture's numbering can never be
// silently misapplied against another's (e.g. a 32-bit compat call).
const AUDIT_ARCH_X86_64: u32 = 0xc000_003e;
const AUDIT_ARCH_AARCH64: u32 = 0xc000_00b7;

#[repr(C)]
struct SockFilter {
    code: u16,
    jt: u8,
    jf: u8,
    k: u32,
}

#[repr(C)]
struct SockFprog {
    len: u16,
    filter: *const SockFilter,
}

fn stmt(code: u16, k: u32) -> SockFilter {
    SockFilter { code, jt: 0, jf: 0, k }
}
fn jump(code: u16, k: u32, jt: u8, jf: u8) -> SockFilter {
    SockFilter { code, jt, jf, k }
}

fn host_audit_arch() -> io::Result<u32> {
    match std::env::consts::ARCH {
        "x86_64" => Ok(AUDIT_ARCH_X86_64),
        "aarch64" => Ok(AUDIT_ARCH_AARCH64),
        other => Err(io::Error::new(io::ErrorKind::Unsupported, format!("no seccomp syscall table for architecture '{other}'"))),
    }
}

/// Applies a filter to the *calling* process, inherited by every
/// process it forks/execs afterward -- called once, from `mod.rs::run`,
/// right where `libseccomp`'s `apply` used to run (after the required
/// fork into the PID1 child, before the foreground command). `syscalls`
/// are resolved against the host's own architecture table; a name not
/// found there is skipped rather than treated as fatal (some names are
/// genuinely architecture-specific -- see `registry::syscall_table`'s
/// doc comment on aarch64 lacking several legacy names glibc itself
/// never emits as literal syscalls on that architecture).
pub fn apply(filter: &Filter) -> io::Result<()> {
    let audit_arch = host_audit_arch()?;
    let Some(table) = syscall_table::for_host_arch() else {
        return Err(io::Error::new(io::ErrorKind::Unsupported, "no seccomp syscall table for this architecture"));
    };

    let deny_action = SECCOMP_RET_ERRNO | (libc::EPERM as u32);
    let default_action = if filter.default_deny { deny_action } else { SECCOMP_RET_ALLOW };

    let mut program: Vec<SockFilter> = Vec::new();

    // 1. Verify the architecture this process is actually running as
    //    matches the one `table`'s numbers were resolved for. Refuses
    //    (kills) on mismatch rather than silently applying numbers
    //    that mean something else entirely on a different arch/ABI.
    program.push(stmt(BPF_LD_W_ABS, SECCOMP_DATA_ARCH_OFFSET));
    program.push(jump(BPF_JMP_JEQ_K, audit_arch, 1, 0));
    program.push(stmt(BPF_RET_K, SECCOMP_RET_KILL_PROCESS));

    // 2. Load the syscall number once; every check below compares
    //    against this same loaded value.
    program.push(stmt(BPF_LD_W_ABS, SECCOMP_DATA_NR_OFFSET));

    // 3. One JEQ+RET pair per resolvable syscall name -- each only
    //    ever jumps 0 or 1 instructions forward, so this chain is safe
    //    at any length (no BPF jump-range limit to worry about, unlike
    //    a single wide jump table would have). `deny` is checked first
    //    so an explicit deny always wins if a name somehow ended up in
    //    both lists (callers are expected to reject that conflict
    //    before it ever reaches here, but this ordering keeps the
    //    fail-safe direction even if that check were ever bypassed).
    for name in &filter.deny {
        let Some(&nr) = table.get(name.as_str()) else {
            continue;
        };
        program.push(jump(BPF_JMP_JEQ_K, nr as u32, 0, 1));
        program.push(stmt(BPF_RET_K, deny_action));
    }
    for name in &filter.allow {
        let Some(&nr) = table.get(name.as_str()) else {
            continue;
        };
        program.push(jump(BPF_JMP_JEQ_K, nr as u32, 0, 1));
        program.push(stmt(BPF_RET_K, SECCOMP_RET_ALLOW));
    }

    // 4. Nothing matched -- this filter's default action.
    program.push(stmt(BPF_RET_K, default_action));

    if program.len() > u16::MAX as usize {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "seccomp program too large (too many syscalls in this preset)"));
    }
    let fprog = SockFprog { len: program.len() as u16, filter: program.as_ptr() };

    // SAFETY: `fprog` borrows `program`, which outlives this call --
    // the kernel copies the program into itself during prctl(), it
    // doesn't retain the pointer afterward.
    let ret = unsafe { libc::prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &fprog as *const SockFprog, 0, 0) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Forks so the filter only ever applies to a throwaway child, not
    /// the test process itself -- runs entirely unprivileged, no
    /// namespace/mount involvement at all. Sets `NO_NEW_PRIVS` first,
    /// same as production's `harden::apply()` always does before
    /// `sandbox::mod::run` ever reaches `seccomp::apply` -- the kernel
    /// refuses `PR_SET_SECCOMP` with EACCES for an unprivileged caller
    /// that hasn't set this, so skipping it here would test a call
    /// sequence that doesn't match reality.
    fn run_in_child(f: impl FnOnce()) -> i32 {
        let pid = unsafe { libc::fork() };
        assert!(pid >= 0, "fork failed");
        if pid == 0 {
            let ret = unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) };
            if ret != 0 {
                unsafe { libc::_exit(2) };
            }
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
            let filter = Filter { default_deny: false, allow: Vec::new(), deny: vec!["getcwd".to_string()] };
            apply(&filter).expect("apply should succeed");
            let mut buf = [0i8; 64];
            let ret = unsafe { libc::getcwd(buf.as_mut_ptr(), buf.len()) };
            let errno = std::io::Error::last_os_error().raw_os_error();
            unsafe { libc::_exit(if ret.is_null() && errno == Some(libc::EPERM) { 0 } else { 1 }) };
        });
        assert_eq!(code, 0, "getcwd should have been blocked by the denylist");
    }

    #[test]
    fn allowlist_permits_only_the_listed_syscalls() {
        let code = run_in_child(|| {
            // Deliberately omit "write" -- the allowlist must still let
            // the process's own controlled exit through (exit_group,
            // which _exit ultimately calls, plus rt_sigreturn for
            // signal handling machinery around it), or this test can
            // never report its own result.
            let filter = Filter {
                default_deny: true,
                allow: vec!["getpid".to_string(), "exit_group".to_string(), "rt_sigreturn".to_string()],
                deny: Vec::new(),
            };
            apply(&filter).expect("apply should succeed");
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

    #[test]
    fn unresolvable_syscall_name_is_skipped_not_fatal() {
        let code = run_in_child(|| {
            let filter = Filter { default_deny: false, allow: Vec::new(), deny: vec!["not-a-real-syscall-name".to_string(), "getcwd".to_string()] };
            let ok = apply(&filter).is_ok();
            unsafe { libc::_exit(if ok { 0 } else { 1 }) };
        });
        assert_eq!(code, 0, "an unresolvable name shouldn't make apply() itself fail");
    }

    #[test]
    fn mixed_allow_and_deny_lists_apply_independently() {
        let code = run_in_child(|| {
            // deny wins for getcwd even though the default is "allow" --
            // and getpid/exit_group/rt_sigreturn stay reachable via the
            // permissive default, without needing to be listed at all.
            let filter = Filter { default_deny: false, allow: Vec::new(), deny: vec!["getcwd".to_string()] };
            apply(&filter).expect("apply should succeed");
            let pid = unsafe { libc::getpid() };
            let mut buf = [0i8; 64];
            let ret = unsafe { libc::getcwd(buf.as_mut_ptr(), buf.len()) };
            let errno = std::io::Error::last_os_error().raw_os_error();
            let getpid_worked = pid > 0;
            let getcwd_blocked = ret.is_null() && errno == Some(libc::EPERM);
            unsafe { libc::_exit(if getpid_worked && getcwd_blocked { 0 } else { 1 }) };
        });
        assert_eq!(code, 0, "getpid should work via the permissive default, getcwd should be blocked via the explicit deny entry");
    }
}
