// &desc: "btrfs process wrappers: label/resize/used-space queries and subvolume snapshot/delete/show, plus local-time formatting for snapshot names and timestamps."
use std::path::Path;

use crate::error::Result;
use crate::proc;
use crate::size::size_label;

pub fn set_label(mnt_or_dev: &Path, name: &str, mb: u64) {
    let label = format!("{name} [{}]", size_label(mb));
    let target = mnt_or_dev.to_string_lossy().into_owned();
    proc::run_silent("btrfs", &["filesystem", "label", &target, &label]);
}

pub fn mkfs(dev: &str, name: &str, mb: u64) -> Result<()> {
    let label = format!("{name} [{}]", size_label(mb));
    proc::run("mkfs.btrfs", &["-f", "-L", &label, dev])
}

/// Raw `blkid <dev>` output — callers check for `"btrfs"` (already
/// formatted with our filesystem) or `"TYPE="` (has *any* filesystem).
pub fn blkid_output(dev: &str) -> String {
    let out = proc::capture("blkid", &[dev]);
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// Used space inside a mounted btrfs filesystem, in MiB.
pub fn used_mb(mnt: &Path) -> Option<u64> {
    let mnt_s = mnt.to_string_lossy().into_owned();
    let out = proc::capture("df", &["--block-size=1", "--output=used", &mnt_s]);
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut lines = text.lines();
    lines.next()?; // header row
    lines.next()?.trim().parse::<u64>().ok().map(|bytes| bytes / (1024 * 1024))
}

pub fn resize(mnt: &Path, target: &str) -> Result<()> {
    let mnt_s = mnt.to_string_lossy().into_owned();
    proc::run("btrfs", &["filesystem", "resize", target, &mnt_s])
}

pub fn resize_silent(mnt: &Path, target: &str) {
    let mnt_s = mnt.to_string_lossy().into_owned();
    proc::run_silent("btrfs", &["filesystem", "resize", target, &mnt_s]);
}

pub fn snapshot(src: &Path, dest: &Path, readonly: bool) -> Result<()> {
    let src_s = src.to_string_lossy().into_owned();
    let dest_s = dest.to_string_lossy().into_owned();
    if readonly {
        proc::run("btrfs", &["subvolume", "snapshot", "-r", &src_s, &dest_s])
    } else {
        proc::run("btrfs", &["subvolume", "snapshot", &src_s, &dest_s])
    }
}

pub fn delete_subvolume(path: &Path) -> Result<()> {
    let s = path.to_string_lossy().into_owned();
    proc::run("btrfs", &["subvolume", "delete", &s])
}

pub fn delete_subvolume_silent(path: &Path) {
    let s = path.to_string_lossy().into_owned();
    proc::run_silent("btrfs", &["subvolume", "delete", &s]);
}

/// `btrfs subvolume show <path>`'s "Creation time:" line, reformatted to
/// "YYYY-MM-DD HH:MM"; falls back to the path's mtime, then to "unknown".
pub fn creation_time(snap_path: &Path) -> String {
    let path_s = snap_path.to_string_lossy().into_owned();
    let out = proc::capture("btrfs", &["subvolume", "show", &path_s]);
    if out.status.success() {
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            if let Some(idx) = line.find("Creation time:") {
                let after = &line[idx + "Creation time:".len()..];
                let mut parts = after.split_whitespace();
                if let (Some(date), Some(time)) = (parts.next(), parts.next()) {
                    return format!("{date} {time}");
                }
            }
        }
    }
    if let Ok(secs) = snap_path
        .metadata()
        .and_then(|m| m.modified())
        .map(|t| t.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_secs() as i64)
    {
        return format_local_ymd_hm(secs);
    }
    "unknown".to_string()
}

/// Broken-down local time for a Unix timestamp, via the C library (so it
/// respects the system timezone the same way Python's
/// `datetime.fromtimestamp` does) — used instead of pulling in a full
/// date/time crate for two `strftime`-style formats.
fn local_tm(secs: i64) -> libc::tm {
    unsafe {
        let time_t = secs as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&time_t, &mut tm);
        tm
    }
}

pub fn format_local_ymd_hm(secs: i64) -> String {
    let tm = local_tm(secs);
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}",
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday,
        tm.tm_hour,
        tm.tm_min,
    )
}

/// "auto-HH:MM:SS-[DD-MM-YYYY]" — the auto-backup snapshot naming scheme.
pub fn format_auto_snap_name(secs: i64) -> String {
    let tm = local_tm(secs);
    format!(
        "{}{:02}:{:02}:{:02}-[{:02}-{:02}-{:04}]",
        crate::config::AUTO_SNAP_PREFIX,
        tm.tm_hour,
        tm.tm_min,
        tm.tm_sec,
        tm.tm_mday,
        tm.tm_mon + 1,
        tm.tm_year + 1900,
    )
}

pub fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
