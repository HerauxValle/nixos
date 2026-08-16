// &desc: "Public entry point for exec's sandbox mechanics -- wires namespaces/pivot/procfs/devfs/harden/reaper together in the exact order that matters (see run()'s doc comment). CLI wiring (commands/exec/) and Meta-driven configuration call into this; nothing in here knows about vaults or the CLI at all, same separation as btrfs.rs/luks.rs from their callers."
pub mod devfs;
pub mod harden;
pub mod namespaces;
pub mod overlay;
pub mod pivot;
pub mod procfs;
pub mod reaper;
pub mod seccomp;
pub mod syscall_table;

use std::io;
use std::path::Path;

/// Runs `argv` isolated inside `new_root`, using `flags` to pick which
/// namespaces are active (`user` is unconditionally forced on
/// regardless of what's passed in -- see `namespaces::Flags`). Blocks
/// until the foreground command exits and returns its exit code.
///
/// Order matters, confirmed against a known-working reference
/// (`Scripts/Seed/helpers/sd-init.c`, this project's own C container-
/// init binary):
/// 1. `unshare` every requested namespace at once (one call, including
///    mount -- no need to split it out or defer it to a child).
/// 2. Write uid/gid maps immediately -- before anything else touches
///    the mount tree.
/// 3. Detach the whole mount tree from host propagation.
/// 4. If `overlay` is given, mount it onto `new_root` first -- from
///    inside the sandbox's own just-unshared mount namespace, so it's
///    torn down automatically on exit rather than lingering as a real
///    host mount. `new_root` must already exist as a plain (empty)
///    directory in this case; the overlay mount is what actually
///    populates it.
/// 5. Bind-mount `new_root` onto itself (pivot_root needs a real
///    mountpoint, not a plain directory) -- `MS_REC` picks up the
///    overlay mount from step 4 if there was one.
/// 6. Mount `/proc` and `/dev` into `new_root` *now*, while it's still
///    just a subdirectory of the current root, not yet after
///    `pivot_root`. Mounting a fresh procfs *after* `pivot_root`
///    (targeting the post-pivot `/proc`) reliably fails EPERM ("Mount
///    too revealing" per `dmesg`) from an unprivileged user namespace,
///    even with `MS_NOSUID|MS_NODEV|MS_NOEXEC` set -- pre-pivot avoids
///    it. `cas` already runs as real root (auto-elevates via sudo for
///    every command), which the kernel's own "too revealing" check is
///    specifically scoped to exempt -- but the `/proc` mount is still
///    treated as best-effort, not fatal: it's a convenience for
///    programs that read it, not part of the actual security boundary
///    (namespace isolation + pivot_root hold regardless of whether
///    `/proc` exists). A failure here is traced and `exec` continues
///    without `/proc` rather than aborting the whole sandbox.
/// 7. `pivot_root`, chdir, unmount+remove the old root -- `/proc` and
///    `/dev` come along for free, already in place at their final
///    paths.
/// 8. Harden (`NO_NEW_PRIVS` + capability-bounding-set drops).
/// 9. If `seccomp` is given, applied *after* the required fork below,
///    inside the PID1 child only -- never the supervising parent
///    (which just waits and needs no restriction of its own). Inherited
///    by everything PID1 subsequently forks/execs, including the real
///    foreground command.
/// 10. `fork()` -- **required**, not optional, and easy to get
///    catastrophically wrong: per `pid_namespaces(7)`, the process that
///    calls `unshare(CLONE_NEWPID)` never itself joins the new PID
///    namespace -- only its *next forked child* does. If the reap-loop
///    (which ends by SIGKILLing PID -1, "every process I have
///    permission to signal") runs directly in the `unshare`-calling
///    process instead of in a genuine child, that process is still a
///    full member of the *real* host PID namespace with the real
///    user's real signal permissions -- so the "cleanup" kill broadcasts
///    to the user's entire real session, not a sandboxed subtree. This
///    isn't hypothetical: it happened. `reaper::run_as_pid1` also
///    refuses to fire its final kill unless `getpid() == 1` -- a second,
///    independent check -- but the fork here is what makes that
///    condition possible to satisfy honestly.
/// 11. The forked child (now genuinely PID1 of the new PID namespace)
///    forks the real foreground command, reap-loops until it exits,
///    then kills anything left behind *within its own namespace only*.
///
/// `debug`, when true, traces each step to stderr as `[debug] ...` --
/// same prefix/marker `cas`'s own `--debug` flag uses via `ctx.debug`/
/// `debugf!` (color.rs's `auto_line` recognizes the same marker), kept
/// as a plain bool + `eprintln!` here rather than a `Ctx` dependency so
/// this module stays includable, unmodified, by the standalone
/// `sandbox_poc` binary (which has no `Ctx`/`color` of its own).
pub fn run(
    new_root: &Path,
    old_root_relative: &Path,
    flags: &namespaces::Flags,
    argv: &[String],
    debug: bool,
    overlay: Option<overlay::Spec>,
    seccomp_filter: Option<(seccomp::Mode, Vec<String>)>,
) -> io::Result<i32> {
    let real_uid = unsafe { libc::getuid() };
    let real_gid = unsafe { libc::getgid() };

    macro_rules! trace {
        ($($arg:tt)*) => {
            if debug {
                eprintln!("[debug] {}", format_args!($($arg)*));
            }
        };
    }

    namespaces::unshare(flags)?;
    trace!("unshare ok");
    if flags.user {
        namespaces::write_id_maps(real_uid, real_gid)?;
        trace!("write_id_maps ok");
    }
    pivot::make_root_private()?;
    trace!("make_root_private ok");
    if let Some(spec) = &overlay {
        overlay::mount(new_root, spec)?;
        trace!("overlay mounted onto new_root");
    }
    pivot::bind_mount_self(new_root)?;
    trace!("bind_mount_self ok");
    match procfs::mount_proc(&new_root.join("proc")) {
        Ok(()) => trace!("mount_proc ok (pre-pivot)"),
        Err(e) => trace!("mount_proc failed, continuing without /proc: {e}"),
    }
    devfs::setup(&new_root.join("dev"))?;
    trace!("devfs ok (pre-pivot)");
    pivot::pivot(new_root, old_root_relative)?;
    trace!("pivot ok");
    harden::apply()?;
    trace!("harden ok");

    // Required fork -- see point 8/9 above. Only this child is a real
    // member of the new PID namespace; the reap-loop and its cleanup
    // kill(-1, SIGKILL) must run here, never in the calling process.
    let pid1_child = unsafe { libc::fork() };
    if pid1_child < 0 {
        return Err(io::Error::last_os_error());
    }
    if pid1_child == 0 {
        if let Some((mode, syscalls)) = seccomp_filter {
            match seccomp::apply(mode, &syscalls) {
                Ok(()) => trace!("seccomp filter applied"),
                Err(e) => {
                    eprintln!("[x] seccomp filter failed to apply: {e}");
                    std::process::exit(1);
                }
            }
        }
        trace!("pid1_child: forking foreground command, argv={argv:?}");
        let code = reaper::run_as_pid1(argv)?;
        std::process::exit(code);
    }

    let mut status: libc::c_int = 0;
    let ret = unsafe { libc::waitpid(pid1_child, &mut status, 0) };
    if ret < 0 {
        return Err(io::Error::last_os_error());
    }
    let code = if libc::WIFEXITED(status) { libc::WEXITSTATUS(status) } else { 1 };
    trace!("pid1_child exited with code {code}");
    Ok(code)
}
