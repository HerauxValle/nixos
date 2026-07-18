// &desc: "Loop-device and udev plumbing run as the real (non-root) user via udisksctl, plus the chown-back-to-user helper every command needs after a privileged op."
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Output, Stdio};

use crate::error::Result;
use crate::proc;

/// (uid, gid) of the real invoking user. Read from SUDO_UID/SUDO_GID —
/// always set by sudo once this process has self-elevated — falling back
/// to the process's own ids if launched as root directly.
pub fn real_user_ids() -> (u32, u32) {
    let uid = std::env::var("SUDO_UID")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or_else(|| unsafe { libc::getuid() });
    let gid = std::env::var("SUDO_GID")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or_else(|| unsafe { libc::getgid() });
    (uid, gid)
}

pub fn chown_to_real_user(path: &Path) -> Result<()> {
    let (uid, gid) = real_user_ids();
    std::os::unix::fs::chown(path, Some(uid), Some(gid))?;
    Ok(())
}

/// Run `program` as the real user instead of root — needed for
/// udisksctl/lsblk calls that must see *that* user's udisks session
/// (mounts made under a root shell aren't visible to a plain root lsblk).
pub fn run_as_user(program: &str, args: &[&str]) -> Output {
    let (uid, gid) = real_user_ids();
    Command::new(program)
        .args(args)
        .uid(uid)
        .gid(gid)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .unwrap_or_else(|_| Output {
            status: std::os::unix::process::ExitStatusExt::from_raw(-1),
            stdout: Vec::new(),
            stderr: Vec::new(),
        })
}

/// Register `img` as a udisks loop device under the real user, so
/// KDE/Dolphin's own udisks session sees it. Returns the `/dev/loopN`
/// path on success.
pub fn loop_setup(img: &Path) -> Option<String> {
    let img_str = img.to_string_lossy().into_owned();
    let out = run_as_user("udisksctl", &["loop-setup", "-f", &img_str, "--no-user-interaction"]);
    if !out.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    let idx = stdout.find("/dev/loop")?;
    let digits: String = stdout[idx + "/dev/loop".len()..]
        .chars()
        .take_while(char::is_ascii_digit)
        .collect();
    if digits.is_empty() {
        None
    } else {
        Some(format!("/dev/loop{digits}"))
    }
}

pub fn udev_retrigger(dev: &str) {
    proc::run_silent("udevadm", &["trigger", "--action=change", dev]);
    proc::run_silent("udevadm", &["settle"]);
}

/// Force udisks to notice a resized image file's new size, so Dolphin/KDE
/// shows the right size afterward: if a loop device already exists for
/// this file, cycle it with `losetup -c` (cheap, in place); otherwise set
/// one up as the real user and immediately tear it down again, which is
/// enough to make udisks re-probe the file.
pub fn refresh_size(img: &Path) {
    let img_str = img.to_string_lossy().into_owned();
    let lo = proc::capture("losetup", &["-j", &img_str]);
    let stdout = String::from_utf8_lossy(&lo.stdout);
    for line in stdout.lines() {
        if let Some(loop_dev) = line.split(':').next().map(str::trim).filter(|s| !s.is_empty()) {
            proc::run_silent("losetup", &["-c", loop_dev]);
            proc::run_silent("udevadm", &["settle"]);
            return;
        }
    }

    let Some(loop_dev) = loop_setup(img) else {
        return;
    };
    proc::run_silent("udevadm", &["settle"]);
    let (uid, gid) = real_user_ids();
    let _ = Command::new("udisksctl")
        .args(["loop-delete", "-b", &loop_dev, "--no-user-interaction"])
        .uid(uid)
        .gid(gid)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    proc::run_silent("udevadm", &["settle"]);
}
