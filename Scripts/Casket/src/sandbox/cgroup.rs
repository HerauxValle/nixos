// &desc: "cgroup v2 resource limits for exec sessions -- creates /sys/fs/cgroup/cas-exec/<session>, delegates memory/cpu/pids controllers down to it, applies limits, and joins the sandboxed PID1 child before pivot_root (the cgroup.procs fd is opened on the host side and stays valid across pivot -- file descriptors don't care about mount namespace changes). Nothing here persists past the session: cleanup rmdir's the session directory once every process in it has exited. cas already runs as real root (see main.rs's self-elevation), so this is a plain root-writes-to-sysfs operation, not a namespaced/rootless one -- the one place exec's sandbox mechanics aren't unprivileged, matching the plan's explicit exception for cgroups."
use std::fs;
use std::fs::File;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

const ROOT: &str = "/sys/fs/cgroup";
const PARENT_NAME: &str = "cas-exec";
const CONTROLLERS: &[&str] = &["memory", "cpu", "pids"];

/// Resource limits for one `exec` session -- `None` fields are left at
/// the kernel's own default ("max", i.e. unlimited).
#[derive(Default, Clone)]
pub struct Spec {
    /// e.g. `"512M"` -- parsed by `parse_bytes`, written verbatim in
    /// bytes to `memory.max`.
    pub mem: Option<String>,
    /// Percent of one CPU (50 = half a core), written to `cpu.max` as
    /// `<quota> 100000`.
    pub cpu: Option<u32>,
    pub pids: Option<u32>,
}

impl Spec {
    pub fn is_empty(&self) -> bool {
        self.mem.is_none() && self.cpu.is_none() && self.pids.is_none()
    }
}

/// An open, not-yet-joined session cgroup -- `join_self` is called from
/// inside the forked PID1 child (see `sandbox::run`), `cleanup` from the
/// supervising parent after the session exits.
pub struct Handle {
    dir: PathBuf,
    procs: File,
}

impl Handle {
    /// Writes the *calling* process's own pid into `cgroup.procs`,
    /// moving it (and, from then on, everything it forks) into this
    /// cgroup. Must be called before `pivot_root` makes the host
    /// filesystem unreachable by path -- `procs` was opened back when
    /// `/sys/fs/cgroup` was still reachable, so the fd itself stays
    /// valid regardless of what happens to the mount namespace
    /// afterward.
    pub fn join_self(&self) -> io::Result<()> {
        let pid = unsafe { libc::getpid() };
        (&self.procs).write_all(pid.to_string().as_bytes())
    }
}

/// rmdir's the session directory on every return path out of
/// `sandbox::run` -- not just the success path after `waitpid`. A
/// `Handle` can be dropped after an early failure too (e.g. this dev
/// box's known pre-fork pivot_root limitation), and without this the
/// session directory would leak on every such failure, never on just
/// the happy path. `std::process::exit`, which the PID1 child always
/// uses instead of returning, skips destructors entirely (documented
/// behavior) -- so the child's copy of `Handle` (duplicated by `fork`)
/// never runs this, only the supervising parent's does, exactly once.
impl Drop for Handle {
    fn drop(&mut self) {
        for attempt in 0..10 {
            if fs::remove_dir(&self.dir).is_ok() {
                return;
            }
            if attempt < 9 {
                std::thread::sleep(Duration::from_millis(50));
            }
        }
    }
}

/// `true` if `/sys/fs/cgroup` is a real cgroup v2 unified hierarchy --
/// `cgroup.controllers` only exists there, never under v1 or a plain
/// tmpfs. Callers should treat `false` as "resource limits aren't
/// available on this host" and refuse cleanly, not attempt the writes
/// anyway.
pub fn is_available() -> bool {
    Path::new(ROOT).join("cgroup.controllers").is_file()
}

/// Creates (or reuses) `/sys/fs/cgroup/cas-exec/<session>`, delegates
/// `memory`/`cpu`/`pids` down to it, applies `spec`'s limits, and opens
/// `cgroup.procs` for the later `join_self` call. `session` should be
/// unique per invocation (the caller uses the exec process's own pid) --
/// a name collision would silently share a cgroup between two unrelated
/// sessions.
pub fn prepare(session: &str, spec: &Spec) -> io::Result<Handle> {
    if !is_available() {
        return Err(io::Error::new(io::ErrorKind::Unsupported, "no cgroup v2 hierarchy at /sys/fs/cgroup -- cgroup limits aren't available on this host"));
    }

    let parent = Path::new(ROOT).join(PARENT_NAME);
    fs::create_dir_all(&parent)?;
    sweep_stale(&parent);

    delegate(&PathBuf::from(ROOT))?;
    delegate(&parent)?;

    let dir = parent.join(session);
    fs::create_dir_all(&dir)?;

    if let Some(mem) = &spec.mem {
        let bytes = parse_bytes(mem).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, format!("invalid memory limit '{mem}' -- expected e.g. '512M', '1G', or a plain byte count")))?;
        fs::write(dir.join("memory.max"), bytes.to_string())?;
    }
    if let Some(percent) = spec.cpu {
        let quota = (percent as u64) * 1000;
        fs::write(dir.join("cpu.max"), format!("{quota} 100000"))?;
    }
    if let Some(pids) = spec.pids {
        fs::write(dir.join("pids.max"), pids.to_string())?;
    }

    let procs = File::options().write(true).open(dir.join("cgroup.procs"))?;
    Ok(Handle { dir, procs })
}

/// Enables `CONTROLLERS` in `dir`'s own `cgroup.subtree_control` --
/// makes them available to `dir`'s children. Idempotent: re-enabling an
/// already-enabled controller is a harmless no-op per the kernel, so
/// errors here (e.g. a controller not present on this host at all) are
/// traced away rather than failing the whole session over a controller
/// that simply isn't compiled in.
fn delegate(dir: &Path) -> io::Result<()> {
    let request: String = CONTROLLERS.iter().map(|c| format!("+{c} ")).collect();
    // Best-effort: some hosts don't have every controller (e.g. `pids`
    // disabled in a minimal kernel config) -- one missing controller
    // shouldn't block the ones that do exist, so this writes the whole
    // set at once and swallows the error, same as the individual limit
    // writes above intentionally don't for the controllers a user
    // actually asked to limit.
    let _ = fs::write(dir.join("cgroup.subtree_control"), request.trim_end());
    Ok(())
}

/// rmdir's `dir`'s session subdirectories that have no processes left in
/// them -- covers cleanup that a prior session couldn't run itself
/// (e.g. `cas` killed externally before it reached its own `cleanup`
/// call). Best-effort: any error per-entry is skipped, never fatal.
fn sweep_stale(parent: &Path) {
    let Ok(entries) = fs::read_dir(parent) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let empty = fs::read_to_string(path.join("cgroup.procs")).map(|s| s.trim().is_empty()).unwrap_or(false);
        if empty {
            let _ = fs::remove_dir(&path);
        }
    }
}

/// Parses `"512M"`, `"1G"`, `"2048K"`, or a bare byte count into bytes.
/// Powers of 1024 (Ki/Mi/Gi in all but name) -- matches how
/// `memory.max` itself is just a plain byte integer with no suffix
/// support, so this is purely a convenience for the human-facing side
/// of `sandbox cgroups set`.
pub fn parse_bytes(s: &str) -> Option<u64> {
    let s = s.trim();
    let (num, mult) = match s.chars().last()? {
        'k' | 'K' => (&s[..s.len() - 1], 1024u64),
        'm' | 'M' => (&s[..s.len() - 1], 1024 * 1024),
        'g' | 'G' => (&s[..s.len() - 1], 1024 * 1024 * 1024),
        _ => (s, 1),
    };
    num.trim().parse::<u64>().ok().and_then(|n| n.checked_mul(mult))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_bytes_handles_suffixes() {
        assert_eq!(parse_bytes("512"), Some(512));
        assert_eq!(parse_bytes("1K"), Some(1024));
        assert_eq!(parse_bytes("512M"), Some(512 * 1024 * 1024));
        assert_eq!(parse_bytes("1G"), Some(1024 * 1024 * 1024));
        assert_eq!(parse_bytes("2g"), Some(2 * 1024 * 1024 * 1024));
        assert_eq!(parse_bytes("not-a-number"), None);
        assert_eq!(parse_bytes(""), None);
    }

    #[test]
    fn spec_is_empty_reflects_all_three_fields() {
        assert!(Spec::default().is_empty());
        assert!(!Spec { mem: Some("1G".to_string()), ..Default::default() }.is_empty());
        assert!(!Spec { cpu: Some(50), ..Default::default() }.is_empty());
        assert!(!Spec { pids: Some(64), ..Default::default() }.is_empty());
    }
}
