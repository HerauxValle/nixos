// &desc: "Mount guard for a 2FA keyfile living on a removable drive: auto-mounts it via udisksctl if present-but-unmounted, retries 30s for udev at boot, unmounts again on drop."
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use serde_json::Value;

use crate::ctx::Ctx;
use crate::proc;
use crate::udisks::run_as_user;

/// Holds the keyfile path to actually use (`None` means the removable
/// device isn't present — caller should skip 2FA). If this guard is the
/// one that mounted the drive, it unmounts it again on drop.
pub struct KeyfileMount {
    pub path: Option<PathBuf>,
    unmount_dev: Option<String>,
}

impl Drop for KeyfileMount {
    fn drop(&mut self) {
        if let Some(dev) = &self.unmount_dev {
            proc::run_silent("udisksctl", &["unmount", "--no-user-interaction", "-b", dev]);
        }
    }
}

fn plain(path: Option<&Path>) -> KeyfileMount {
    KeyfileMount { path: path.map(Path::to_path_buf), unmount_dev: None }
}

/// If `kf_path` lives under `/run/media/*` or `/media/*` (a removable
/// mount): device not present -> skip; present & mounted -> use as-is;
/// present & unmounted -> mount it here, unmount again when the returned
/// guard drops. Any other path is returned unchanged and never touched.
pub fn ensure_keyfile_mounted(ctx: &Ctx, kf_path: Option<&Path>) -> KeyfileMount {
    let Some(kf_path) = kf_path else {
        return plain(None);
    };

    // Detect "removable" from the raw path string, not a resolved one —
    // under sudo the mountpoint directory may not exist yet, so anything
    // that walks the filesystem here would be premature.
    let kf_str = kf_path.to_string_lossy();
    let removable = kf_str.starts_with("/run/media/") || kf_str.starts_with("/media/");
    if !removable {
        return plain(Some(kf_path));
    }

    // Mountpoint prefix is the first 5 path components: /, run, media,
    // <user>, <LABEL>.
    let parts: Vec<&std::ffi::OsStr> = kf_path.iter().collect();
    if parts.len() < 5 {
        return plain(Some(kf_path));
    }
    let probe: PathBuf = parts[..5].iter().collect();
    let probe = probe.to_string_lossy().into_owned();

    let deadline = Instant::now() + Duration::from_secs(30);
    let (mut found_uuid, mut current_mount);
    loop {
        let data = lsblk_json();
        let devices = data
            .get("blockdevices")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        (found_uuid, current_mount) = find_device(&devices, &probe);
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

    if let Some(mount) = current_mount {
        let full = PathBuf::from(mount).join(relative_tail(kf_path, 5));
        return plain(Some(&full));
    }

    let dev = format!("/dev/disk/by-uuid/{uuid}");
    if !ctx.quiet {
        eprintln!("[i] mounting removable device {uuid} ...");
    }
    let out = proc::capture("udisksctl", &["mount", "--no-user-interaction", "-b", &dev]);
    if !out.status.success() {
        if !ctx.quiet {
            eprintln!(
                "[!] mount failed: {}, skipping keyfile",
                String::from_utf8_lossy(&out.stderr).trim()
            );
        }
        return plain(None);
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    let actual_kf = match stdout.trim().rsplit_once(" at ") {
        Some((_, mountpoint)) => PathBuf::from(mountpoint).join(relative_tail(kf_path, 5)),
        None => kf_path.to_path_buf(),
    };

    KeyfileMount { path: Some(actual_kf), unmount_dev: Some(dev) }
}

/// The path components of `kf_path` after the first `n` (the mountpoint
/// prefix), rejoined — e.g. `vaults/name.key`.
fn relative_tail(kf_path: &Path, n: usize) -> PathBuf {
    kf_path.iter().skip(n).collect()
}

fn find_device(devices: &[Value], probe: &str) -> (Option<String>, Option<String>) {
    for d in devices {
        let label = d.get("label").and_then(Value::as_str).unwrap_or("");
        let uuid = d.get("uuid").and_then(Value::as_str).unwrap_or("");
        if (!label.is_empty() && probe.contains(label)) || (!uuid.is_empty() && probe.contains(uuid)) {
            let mountpoint = d.get("mountpoint").and_then(Value::as_str).map(str::to_string);
            return (Some(uuid.to_string()), mountpoint);
        }
        if let Some(children) = d.get("children").and_then(Value::as_array) {
            let (u, m) = find_device(children, probe);
            if u.is_some() {
                return (u, m);
            }
        }
    }
    (None, None)
}

/// Run lsblk as the real (non-root) user so udisks user-session mounts
/// are visible — a root-owned lsblk wouldn't see them.
pub fn lsblk_json() -> Value {
    let out = run_as_user("lsblk", &["-J", "-o", "NAME,UUID,LABEL,MOUNTPOINT"]);
    if !out.status.success() {
        return Value::Null;
    }
    serde_json::from_slice(&out.stdout).unwrap_or(Value::Null)
}
