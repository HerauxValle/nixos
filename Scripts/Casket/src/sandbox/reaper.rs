// &desc: "PID1 reap loop for exec's sandbox. After unshare(CLONE_NEWPID), the calling process itself stays in the OLD pid namespace -- only its next fork()'d child becomes PID1 of the new one. That child can't just exec the user's command directly: anything it (or something reparented to it) forks needs a reaper, or zombies pile up forever. So PID1 forks once more for the real foreground command, waitpid-loops reaping everything, and on the foreground command's exit kills whatever's still running in the namespace before exiting itself."
use std::ffi::CString;
use std::io;



/// Runs inside the process that's already PID1 of the new PID
/// namespace (call this right after the mount/pivot/proc/dev setup is
/// done, from the fork()'d child described above). Forks the real
/// command, reaps every zombie until the foreground child exits, then
/// SIGKILLs anything left in the namespace and returns the foreground
/// command's exit code.
pub fn run_as_pid1(argv: &[String]) -> io::Result<i32> {
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
        // `getpid` syscall itself just failed, almost always because an
        // active seccomp filter (a `default = "deny"` custom profile
        // that forgot to allow `getpid`, most commonly) is blocking it
        // with `EPERM`, not because of a namespace problem. `getpid`/
        // `wait4`/`kill`/`fork`/`exit_group` are needed by this reaper
        // itself, not just whatever command `exec` is running -- a
        // strict default-deny profile needs to allow those explicitly.
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
        exec(argv)?; // never returns on success
        unreachable!("exec only returns on failure, which already returned Err above");
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
    Ok(exit_code(status))
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
