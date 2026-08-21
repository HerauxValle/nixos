// &desc: "PID1 reap loop for exec's sandbox. After unshare(CLONE_NEWPID), the calling process itself stays in the OLD pid namespace -- only its next fork()'d child becomes PID1 of the new one. That child can't just exec the user's command directly: anything it (or something reparented to it) forks needs a reaper, or zombies pile up forever. So PID1 forks once more for the real foreground command, waitpid-loops reaping everything, and on the foreground command's exit kills whatever's still running in the namespace before exiting itself."
use std::ffi::CString;
use std::io;

use super::seccomp;

/// Runs inside the process that's already PID1 of the new PID
/// namespace (call this right after the mount/pivot/proc/dev setup is
/// done, from the fork()'d child described above). Forks the real
/// command, reaps every zombie until the foreground child exits, then
/// SIGKILLs anything left in the namespace and returns the foreground
/// command's exit code.
///
/// `seccomp_filter`, if given, is applied *only* inside the second fork
/// below, immediately before that child's own `execvp` -- never to this
/// reaper process itself. This reaper still needs `getpid`/`wait4`/
/// `kill`/`fork` (the second fork, right here) plus everything the Rust
/// runtime and its own error-reporting path need (`write`, `mmap`,
/// `rt_sigreturn`, `tgkill`, ...) to keep functioning regardless of
/// what a custom profile's allow list covers -- see `mod.rs::run`'s
/// doc comment on step 9 for the full account of what went wrong when
/// the filter used to apply here instead (a `default: deny` custom
/// profile silenced this function's own error message by blocking the
/// `write()` call meant to print it, rather than the getpid() check
/// below simply not firing). The foreground command -- and everything
/// *it* subsequently forks/execs -- still inherits the filter exactly
/// as before, since it's applied before `execvp`, not after.
pub fn run_as_pid1(argv: &[String], seccomp_filter: Option<seccomp::Filter>) -> io::Result<i32> {
    // Captured before `seccomp_filter` is moved into the child branch
    // below -- used only for the diagnostic after the reap loop, to
    // decide whether an unexplained crash is worth a seccomp-specific
    // hint. Doesn't affect what's actually allowed/denied; that's still
    // entirely `filter`'s own `default_deny`/`allow`/`deny` fields, read
    // unmodified by `seccomp::apply` below.
    let had_seccomp_filter = seccomp_filter.is_some();

    // Second, independent safety check on top of mod.rs::run's required
    // fork (see its doc comment): `kill(-1, SIGKILL)` below means
    // "every process I have permission to signal," scoped to this
    // process's PID namespace *only if* this process actually is a
    // member of a fresh one -- which is true exactly when its own PID,
    // as it sees itself, is 1. If some future refactor calls this
    // function from the wrong process (the one that called `unshare`
    // itself, not its forked child), that process's own PID within the
    // *real* host namespace is never 1 -- so this refuses to fire the
    // broadcast kill instead of silently signaling the real host's
    // processes. This exact scenario caused a real, live user-session
    // logout once; this check exists specifically to make that
    // structurally impossible to repeat.
    let own_pid = unsafe { libc::getpid() };
    if own_pid == -1 {
        // A real pid is always positive -- -1 specifically means the
        // `getpid` syscall itself just failed. With the filter now
        // applied only around the foreground child's own `execvp`
        // below, this reaper is never itself under a custom profile's
        // restriction, so this shouldn't fire from that cause anymore
        // -- it's kept as defense-in-depth (e.g. against some future
        // change that reintroduces an early `seccomp::apply`, or an
        // unrelated cause of `getpid` failing) rather than because it's
        // expected to be reachable in normal operation. If it ever does
        // fire, the message still points at the historically most
        // likely cause.
        return Err(io::Error::new(
            io::ErrorKind::Other,
            "refusing to run as PID1 reaper: getpid() itself failed -- if a custom seccomp profile with default=\"deny\" is active, it needs to explicitly allow getpid/wait4/kill/fork/clone/exit_group as well, since this sandbox's own PID1 supervisor needs those, not just the command being run".to_string(),
        ));
    }
    if own_pid != 1 {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("refusing to run as PID1 reaper: own pid is {own_pid}, not 1 -- this process is not actually a member of an isolated PID namespace"),
        ));
    }

    let child = unsafe { libc::fork() };
    if child < 0 {
        return Err(io::Error::last_os_error().into());
    }
    if child == 0 {
        // The filter is applied *here*, in this freshly-forked child,
        // immediately before `execvp` -- not any earlier, and not in
        // the reaper above. This is the only process it's ever meant to
        // constrain: `execve` inherits it across the exec, so the
        // foreground command (and everything it goes on to fork/exec
        // itself) is fully covered from its very first instruction,
        // while nothing before this point -- namespace/mount setup,
        // this reaper's own bookkeeping -- ever had to satisfy someone
        // else's allow list. See `mod.rs::run`'s doc comment (step 9)
        // for why applying it any earlier broke this exact error-
        // reporting path under a restrictive custom profile.
        //
        // Errors here (filter or exec) are reported and exit this
        // child directly, deliberately not via `?`/`Err` -- this
        // function's caller (`mod.rs::run`) is running in a process
        // that `fork()` already split in two; letting an `Err` unwind
        // back up through it from *this* child would resume the
        // original caller's own post-`sandbox::run` code a second time,
        // in a process the caller never intended to keep running,
        // rather than actually reporting the failure.
        if let Some(filter) = seccomp_filter {
            if let Err(e) = seccomp::apply(&filter) {
                eprintln!("[x] seccomp filter failed to apply: {e}");
                std::process::exit(1);
            }
        }
        if let Err(e) = exec(argv) {
            eprintln!("[x] exec failed: {e}");
            std::process::exit(1);
        }
        unreachable!("exec only returns on failure, which already exited above");
    }

    let mut foreground_status: Option<i32> = None;
    loop {
        let mut status: libc::c_int = 0;
        let reaped = unsafe { libc::waitpid(-1, &mut status, 0) };
        if reaped == child {
            foreground_status = Some(status);
        }
        if reaped < 0 {
            // ECHILD -- no more children of any kind left to reap.
            break;
        }
        if foreground_status.is_some() {
            // The foreground command exited. Kill everything else
            // still running in this PID namespace (children reparented
            // to us, anything they spawned) rather than leaving it
            // orphaned in the background once the caller tears the
            // namespace down.
            unsafe {
                libc::kill(-1, libc::SIGKILL);
            }
            // Drain remaining zombies from that kill before returning.
            loop {
                let mut s = 0;
                if unsafe { libc::waitpid(-1, &mut s, 0) } < 0 {
                    break;
                }
            }
            break;
        }
    }

    let status = foreground_status.unwrap_or(0);
    // A restrictive custom profile (`default: "deny"` with an allow
    // list that omits basics like `write`/`exit_group`/`mmap`/
    // `rt_sigreturn`) doesn't just deny those calls with EPERM the way
    // the command itself might handle gracefully -- for a program that
    // has no path for a syscall failing that "can't" fail (glibc's own
    // startup, or a Rust binary's panic/print machinery reacting to a
    // *previous* denied call by trying to report it, itself via more
    // denied calls), the practical result is a fatal signal, not a
    // clean exit. That child is under the filter and genuinely cannot
    // report why -- it may not even be able to make the syscalls a
    // clear error message would need, which is exactly the silent-
    // failure trap this whole mechanism exists to avoid (see `mod.rs::
    // run`'s step 9 doc comment for the full account of the same
    // problem previously hitting this reaper itself). This reaper is
    // never under the filter, so it can safely say what the command
    // itself couldn't: a plausible cause, not a certainty (the command
    // could just as easily have crashed for its own unrelated reasons),
    // hence "may have" rather than a flat assertion.
    if had_seccomp_filter && libc::WIFSIGNALED(status) {
        let sig = libc::WTERMSIG(status);
        if matches!(sig, libc::SIGSEGV | libc::SIGABRT | libc::SIGBUS | libc::SIGILL | libc::SIGSYS) {
            eprintln!(
                "[x] sandboxed command terminated by signal {sig} ({}) while a custom seccomp profile was active -- if you're using a 'default: deny' profile, this may mean its allow list is missing a syscall the command (or its runtime's own startup/error-reporting path) needs just to run and fail cleanly, e.g. write/exit_group/mmap/rt_sigreturn, not just what the command explicitly does -- see 'seccomp custom create --help'",
                signal_name(sig)
            );
        }
    }
    Ok(exit_code(status))
}

fn signal_name(sig: libc::c_int) -> &'static str {
    match sig {
        libc::SIGSEGV => "SIGSEGV",
        libc::SIGABRT => "SIGABRT",
        libc::SIGBUS => "SIGBUS",
        libc::SIGILL => "SIGILL",
        libc::SIGSYS => "SIGSYS",
        _ => "signal",
    }
}

fn exit_code(status: libc::c_int) -> i32 {
    if libc::WIFEXITED(status) {
        libc::WEXITSTATUS(status)
    } else if libc::WIFSIGNALED(status) {
        128 + libc::WTERMSIG(status)
    } else {
        1
    }
}

fn exec(argv: &[String]) -> io::Result<()> {
    let c_argv: Vec<CString> = argv.iter().map(|a| CString::new(a.as_bytes()).unwrap()).collect();
    let mut c_ptrs: Vec<*const libc::c_char> = c_argv.iter().map(|c| c.as_ptr()).collect();
    c_ptrs.push(std::ptr::null());
    unsafe {
        libc::execvp(c_ptrs[0], c_ptrs.as_ptr());
    }
    Err(io::Error::last_os_error().into())
}
