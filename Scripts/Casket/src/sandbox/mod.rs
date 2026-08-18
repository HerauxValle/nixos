// &desc: "Public entry point for exec's sandbox mechanics -- wires namespaces/pivot/procfs/devfs/harden/reaper together in the exact order that matters (see run()'s doc comment). CLI wiring (commands/exec/) and Meta-driven configuration call into this; nothing in here knows about vaults or the CLI at all, same separation as btrfs.rs/luks.rs from their callers."
pub mod cgroup;
pub mod devfs;
pub mod harden;
pub mod namespaces;
pub mod netlink;
pub mod network;
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
/// init binary) *and* against a live kernel confirmation that motivated
/// splitting step 1/2 below out from the user namespace -- see
/// `namespaces::unshare_user`'s doc comment:
/// 1. `unshare` every requested namespace *except* user, in one call.
///    Mount is included here -- no need to split it out or defer it to
///    a child.
/// 2. (user namespace intentionally deferred to step 7a, after
///    pivot_root -- not here.)
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
/// 7a. *Now* unshare the user namespace and write uid/gid maps, if
///    `flags.user` is set -- everything that needed real root's
///    capabilities over pre-existing host mounts (overlay, bind-self,
///    procfs, devfs, pivot_root) is already done, so entering the new
///    user namespace here only affects what comes after: hardening and
///    the sandboxed command itself.
/// 8. Harden (`NO_NEW_PRIVS` + capability-bounding-set drops).
/// 9. If `seccomp` is given, applied *after* the required fork below,
///    inside the PID1 child only -- never the supervising parent
///    (which just waits and needs no restriction of its own). Inherited
///    by everything PID1 subsequently forks/execs, including the real
///    foreground command.
/// 9a. If `cgroup_handle` is given, its `cgroup.procs` fd was opened by
///    the caller *before* this function ever unshared or pivoted --
///    `sandbox::cgroup::prepare` runs entirely on the host side, ahead
///    of everything above. The PID1 child writes its own pid through
///    that already-open fd right after the fork (step 10), before
///    seccomp or the foreground command -- the fd itself stays valid
///    across `pivot_root` regardless of mount namespace changes, same
///    trick every proper container runtime uses for exactly this
///    reason (a path-based cgroup join would fail once the host
///    filesystem is unreachable). The supervising parent removes the
///    session's cgroup directory after `waitpid` returns.
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
    seccomp_filter: Option<seccomp::Filter>,
    cgroup_handle: Option<cgroup::Handle>,
    internet: bool,
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

    // Must happen *before* the combined unshare below -- `network::
    // setup_host_side` needs the real host netns to create the veth
    // pair at all (see its own doc comment on why the netlink socket it
    // opens is deliberately kept alive across the later unshare).
    let net_handle = if flags.net && internet {
        let h = network::setup_host_side()?;
        trace!("network: host-side veth+NAT ok");
        Some(h)
    } else {
        None
    };
    // Forked *here* -- strictly before the CLONE_NEWPID-including
    // unshare below, not just before unshare_user -- see
    // `network::spawn_teardown_waiter`'s own doc comment on why: forking
    // after entering the new PID namespace would make this fork itself
    // claim that namespace's PID-1 slot instead of the sandboxed
    // command.
    let teardown_waiter = match &net_handle {
        Some(h) => Some(network::spawn_teardown_waiter(h)?),
        None => None,
    };

    // The user namespace is deliberately unshared *after* every
    // host-mount operation below, not combined into this call -- see
    // `namespaces::unshare_user`'s doc comment for why: `cas` already
    // runs as real root, and a nested user namespace has no capability
    // over pre-existing host mounts (the vault's own mount point
    // included) no matter how its uid map is set.
    namespaces::unshare_without_user(flags)?;
    trace!("unshare (non-user namespaces) ok");
    if flags.net {
        namespaces::bring_up_loopback()?;
        trace!("net namespace: lo brought up (no route out -- isolated by design)");
    }
    if let Some(h) = &net_handle {
        network::setup_sandbox_side(h)?;
        trace!("network: sandbox-side veth+route+up ok -- real outbound connectivity active");
    }
    // Done actively using the Handle now -- hand real cleanup
    // responsibility to the already-forked helper (`teardown_waiter`)
    // before `unshare_user` below restricts this process's own
    // capabilities. See `network::detach`'s doc comment.
    if let Some(h) = net_handle {
        network::detach(h);
    }
    let _teardown_waiter = teardown_waiter;
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
    if flags.user {
        namespaces::unshare_user()?;
        trace!("unshare user ok");
        namespaces::write_id_maps(real_uid, real_gid)?;
        trace!("write_id_maps ok");
    }
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
        if let Some(handle) = &cgroup_handle {
            match handle.join_self() {
                Ok(()) => trace!("cgroup joined"),
                Err(e) => {
                    eprintln!("[x] failed to join cgroup: {e}");
                    std::process::exit(1);
                }
            }
        }
        if let Some(filter) = seccomp_filter {
            match seccomp::apply(&filter) {
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
    // `cgroup_handle`'s Drop impl removes the session directory here
    // (function return) -- and on every early-return path above too,
    // see `cgroup::Handle`'s own doc comment.
    Ok(code)
}
