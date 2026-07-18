// &desc: "Extracts a 2FA keyfile straight from a removable drive's raw blocks via debugfs — device discovery only, never mounts anything, regardless of the drive's current mount state."
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::ctx::Ctx;
use crate::proc::{self, TempKeyfile};
use crate::udisks::run_as_user;

/// Holds the keyfile's content staged in a short-lived, mode-0600 temp
/// file (deleted on drop) so callers keep reading it as a `Path`, same
/// as a local (non-removable) keyfile. `path` is `None` if the
/// removable device isn't present — caller should skip 2FA.
pub struct KeyfileMount {
    pub path: Option<PathBuf>,
    _tmp: Option<TempKeyfile>,
}

fn plain(path: Option<&Path>) -> KeyfileMount {
    KeyfileMount { path: path.map(Path::to_path_buf), _tmp: None }
}

fn staged(bytes: &[u8]) -> KeyfileMount {
    match TempKeyfile::write(bytes) {
        Ok(tmp) => {
            let path = tmp.path().to_path_buf();
            KeyfileMount { path: Some(path), _tmp: Some(tmp) }
        }
        Err(_) => plain(None),
    }
}

/// If `kf_path` lives under `/run/media/*` or `/media/*` (a removable
/// mount): finds the device by UUID/label (retrying up to 30s for udev
/// to enumerate it, e.g. right after login) and reads the keyfile's
/// bytes straight off its raw blocks via `debugfs cat` — no `mount` or
/// `udisksctl mount` call ever happens, so this works identically
/// whether the drive happens to be mounted, unmounted, or was mounted
/// and silently dropped since (all three are indistinguishable and
/// irrelevant to a raw block read). Any other path is returned
/// unchanged and never touched.
pub fn ensure_keyfile_mounted(ctx: &Ctx, kf_path: Option<&Path>) -> KeyfileMount {
    let Some(kf_path) = kf_path else {
        return plain(None);
    };

    // Detect "removable" from the raw path string — under sudo the
    // mountpoint directory may not exist, so nothing here should walk
    // the filesystem.
    let kf_str = kf_path.to_string_lossy();
    let removable = kf_str.starts_with("/run/media/") || kf_str.starts_with("/media/");
    if !removable {
        return plain(Some(kf_path));
    }

    // Mountpoint prefix is the first 5 path components: /, run, media,
    // <user>, <LABEL>. Everything after that is the in-filesystem path
    // debugfs needs.
    let parts: Vec<&std::ffi::OsStr> = kf_path.iter().collect();
    if parts.len() < 5 {
        return plain(Some(kf_path));
    }
    let probe: PathBuf = parts[..5].iter().collect();
    let probe = probe.to_string_lossy().into_owned();
    let fs_path = fs_relative_path(kf_path, 5);

    let deadline = Instant::now() + Duration::from_secs(30);
    let mut found_uuid;
    loop {
        let data = lsblk_json();
        let devices = data
            .get("blockdevices")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        found_uuid = find_uuid(&devices, &probe);
        if found_uuid.is_some() || Instant::now() >= deadline {
            break;
        }
        std::thread::sleep(Duration::from_secs(1));
    }

    let Some(uuid) = found_uuid else {
        if !ctx.quiet {
            eprintln!("[!] keyfile device not found (drive unplugged?), skipping keyfile");
        }
        return plain(None);
    };

    let dev = format!("/dev/disk/by-uuid/{uuid}");
    let out = proc::capture("debugfs", &["-R", &format!("cat {fs_path}"), &dev]);
    // debugfs's "-R <cmd>" mode exits 0 even when the command inside
    // fails (e.g. "File not found by ext2_lookup" on stderr) — empty
    // stdout is the real failure signal, not the exit status.
    if out.stdout.is_empty() {
        if !ctx.quiet {
            let err = String::from_utf8_lossy(&out.stderr);
            eprintln!("[!] could not read keyfile off device, skipping keyfile: {}", err.trim());
        }
        return plain(None);
    }

    staged(&out.stdout)
}

/// `kf_path`'s components after the first `n` (the mountpoint prefix),
/// rejoined as an absolute in-filesystem path, e.g. "/vaults/vaults.key".
fn fs_relative_path(kf_path: &Path, n: usize) -> String {
    let tail: PathBuf = kf_path.iter().skip(n).collect();
    format!("/{}", tail.to_string_lossy())
}

fn find_uuid(devices: &[Value], probe: &str) -> Option<String> {
    for d in devices {
        let label = d.get("label").and_then(Value::as_str).unwrap_or("");
        let uuid = d.get("uuid").and_then(Value::as_str).unwrap_or("");
        if (!label.is_empty() && probe.contains(label)) || (!uuid.is_empty() && probe.contains(uuid)) {
            return Some(uuid.to_string());
        }
        if let Some(children) = d.get("children").and_then(Value::as_array) {
            if let Some(u) = find_uuid(children, probe) {
                return Some(u);
            }
        }
    }
    None
}

/// Run lsblk as the real (non-root) user so udisks user-session mounts
/// are visible when checking whether a device is already mounted
/// elsewhere — a root-owned lsblk wouldn't see them. (Device discovery
/// only; the mount state itself is never acted on.)
fn lsblk_json() -> Value {
    let out = run_as_user("lsblk", &["-J", "-o", "NAME,UUID,LABEL,MOUNTPOINT"]);
    if !out.status.success() {
        return Value::Null;
    }
    serde_json::from_slice(&out.stdout).unwrap_or(Value::Null)
}
