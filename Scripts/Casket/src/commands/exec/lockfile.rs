// &desc: "Liveness marker for a running `cas <vault> exec` session -- one file per session under `.casket/`, named by PID, so `close`/`sandbox disable` (and later rootfs remove/rename) can refuse while a session is live instead of unmounting or deleting out from under it. Stale markers from a killed/crashed session (no matching /proc/<pid>) are pruned automatically rather than permanently blocking future operations."
use std::fs;
use std::path::{Path, PathBuf};

use crate::error::Result;
use crate::vault::Vault;

fn lock_dir(vault: &Vault) -> PathBuf {
    vault.casket_dir()
}

fn own_pid_path(vault: &Vault) -> PathBuf {
    lock_dir(vault).join(format!("exec-{}.lock", std::process::id()))
}

fn pid_from_filename(name: &str) -> Option<u32> {
    name.strip_prefix("exec-")?.strip_suffix(".lock")?.parse().ok()
}

fn process_alive(pid: u32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

/// Whether at least one `exec` session is currently live for `vault`.
/// Prunes any stale marker it finds along the way (a session that was
/// killed rather than exiting cleanly leaves its file behind).
pub fn is_live(vault: &Vault) -> bool {
    let dir = lock_dir(vault);
    let Ok(entries) = fs::read_dir(&dir) else {
        return false;
    };
    let mut live = false;
    for entry in entries.filter_map(|e| e.ok()) {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        let Some(pid) = pid_from_filename(name) else { continue };
        if process_alive(pid) {
            live = true;
        } else {
            let _ = fs::remove_file(entry.path());
        }
    }
    live
}

/// Held for the duration of one `exec` session -- removes its own
/// marker on drop, including on an early return via `?`, so a crashed
/// or error-exited session doesn't need separate cleanup logic.
pub struct Guard {
    path: PathBuf,
}

impl Drop for Guard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

pub fn acquire(vault: &Vault) -> Result<Guard> {
    fs::create_dir_all(lock_dir(vault))?;
    let path = own_pid_path(vault);
    fs::write(&path, b"")?;
    Ok(Guard { path })
}
