// &desc: "Vault struct: resolves a vault's image/mount/mapper paths, locates one by name in cwd/ancestors, and wraps its mount-state checks."
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

use crate::config::MAPPER_PREFIX;
use crate::die;
use crate::error::Result;
use crate::proc;
use crate::secret::resolve_lexically;

pub struct Vault {
    pub name: String,
    pub img: PathBuf,
    pub mnt: PathBuf,
    pub mapper: String,
}

impl Vault {
    /// Build the three well-known paths for `name` under `base`, without
    /// touching the filesystem or requiring the vault to already exist —
    /// used by `create` before the image file is written.
    ///
    /// `name` must be non-empty and free of path separators/`.`/`..` --
    /// `PathBuf::join` treats an empty string as a no-op, so an empty
    /// name previously made `mnt` resolve to `base` itself (the
    /// directory the vault lives in, or the cwd), and every command that
    /// later removed `mnt` -- most seriously `delete`'s
    /// `cleanup_mnt_dir` -- ended up removing that real directory
    /// instead of a vault-specific one. Confirmed live: `cas "" delete`
    /// deleted its own working directory. A `/` in the name has the
    /// same class of problem for the opposite reason (escapes `base`
    /// entirely), same as the rootfs-name traversal fixed in 1.10.22.
    pub fn resolve(base: &Path, name: &str) -> Vault {
        if name.is_empty() || name == "." || name == ".." || name.contains('/') || name.contains('\\') || name.contains('\0') {
            eprintln!("[x] invalid vault name '{name}' -- must be non-empty and can't contain '/', '\\', a null byte, or be '.'/'..'");
            std::process::exit(1);
        }
        Vault {
            name: name.to_string(),
            img: base.join(format!("{name}.img")),
            mnt: base.join(name),
            mapper: format!("{MAPPER_PREFIX}_{name}"),
        }
    }

    /// Locate an existing vault by name: at `path_override` if given,
    /// otherwise searching cwd and up to 4 parent directories.
    pub fn find(name: &str, path_override: Option<&Path>) -> Result<Vault> {
        if let Some(p) = path_override {
            let base = resolve_lexically(p);
            let img = base.join(format!("{name}.img"));
            if !img.exists() {
                recover_interrupted_migration(&base, name);
                if img.exists() {
                    return Ok(Vault::resolve(&base, name));
                }
                die!(
                    "vault '{name}' not found at {}\n    Hint: check the path or run 'cas list' to see all vaults.",
                    img.display()
                );
            }
            return Ok(Vault::resolve(&base, name));
        }

        let cwd = std::env::current_dir()?;
        let mut candidates = vec![cwd.clone()];
        candidates.extend(cwd.ancestors().skip(1).take(4).map(Path::to_path_buf));
        for dir in &candidates {
            if dir.join(format!("{name}.img")).exists() {
                return Ok(Vault::resolve(dir, name));
            }
            recover_interrupted_migration(dir, name);
            if dir.join(format!("{name}.img")).exists() {
                return Ok(Vault::resolve(dir, name));
            }
        }
        die!(
            "vault '{name}' not found (searched cwd and 4 levels up)\n    Hint: run 'cas list' to see all vaults, or cd to where it lives."
        );
    }

    pub fn base(&self) -> &Path {
        self.img.parent().unwrap_or(Path::new("."))
    }

    /// `cas`'s namespaced in-vault directory — `.casket/` at the mount
    /// root. Locked as a whole by ransomwareProtection; `snap_root` (and
    /// any future protected artifact) lives under it.
    pub fn casket_dir(&self) -> PathBuf {
        self.mnt.join(crate::config::CASKET_DIR)
    }

    /// `.rootfs.d/` at the mount root — see `config::ROOTFS_DIR`'s doc
    /// comment for why it's a sibling of `.casket/`, not nested inside.
    pub fn rootfs_dir(&self) -> PathBuf {
        self.mnt.join(crate::config::ROOTFS_DIR)
    }

    /// `.seccomp.d/` at the mount root — see `config::SECCOMP_PROFILES_DIR`'s
    /// doc comment for why it's a sibling of `.casket/`, not nested inside.
    pub fn seccomp_profiles_dir(&self) -> PathBuf {
        self.mnt.join(crate::config::SECCOMP_PROFILES_DIR)
    }

    /// True if `mnt` is a mountpoint (its device differs from its
    /// parent's) — the same test `pathlib.Path.is_mount()` performs.
    pub fn is_mount(&self) -> bool {
        is_mountpoint(&self.mnt)
    }

    pub fn mapper_dev(&self) -> PathBuf {
        PathBuf::from(format!("/dev/mapper/{}", self.mapper))
    }

    pub fn mapper_dev_exists(&self) -> bool {
        self.mapper_dev().exists()
    }

    /// Best-effort `cryptsetup close` — used both for normal teardown and
    /// for clearing a stale mapper left behind by a crashed previous run.
    pub fn close_mapper(&self) {
        proc::run_silent("cryptsetup", &["close", &self.mapper]);
    }

    /// Same teardown, but reports cryptsetup's real failure instead of
    /// swallowing it — for `cas <vault> close --force`, where the whole
    /// point is finding out *why* a stuck mapper won't go away (e.g. its
    /// backing loop device vanished mid-operation, leaving it wedged
    /// "busy" until reboot) rather than a silent no-op.
    pub fn close_mapper_checked(&self) -> Result<()> {
        proc::run("cryptsetup", &["close", &self.mapper])
    }

    pub fn ensure_mnt_dir(&self) -> Result<()> {
        match std::fs::create_dir(&self.mnt) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => Ok(()),
            Err(e) => Err(e.into()),
        }
    }

    /// Remove the (now-empty) mount directory if it's not currently
    /// mounted. Ignores errors, mirroring the original's bare `except
    /// OSError: pass` — the directory may be non-empty, gone already, etc.
    pub fn cleanup_mnt_dir(&self) {
        if self.mnt.exists() && !self.is_mount() {
            let _ = std::fs::remove_dir(&self.mnt);
        }
    }

    pub fn mount(&self, dev: &str) -> Result<()> {
        let mnt_str = self.mnt.to_string_lossy().into_owned();
        proc::run("mount", &[dev, &mnt_str])
    }

    pub fn umount(&self) {
        let mnt_str = self.mnt.to_string_lossy().into_owned();
        proc::run_silent("umount", &[&mnt_str]);
    }

    /// Checked unmount — errors instead of silently swallowing a failure.
    /// Used mid-resize, where an unmount that fails must stop the resize
    /// rather than let it proceed against a still-mounted filesystem.
    pub fn umount_checked(&self) -> Result<()> {
        let mnt_str = self.mnt.to_string_lossy().into_owned();
        proc::run("umount", &[&mnt_str])
    }

    /// Block until an exclusive advisory lock on this vault is held, for
    /// the duration of the returned guard. Every CLI verb that mutates a
    /// vault's on-disk state (metadata trailer, LUKS keyslots, header
    /// room, mounted filesystem) must hold this for its entire run --
    /// confirmed live 2026-08-17 that two `settings` commands racing
    /// against the same vault with no synchronization corrupt its
    /// metadata/keyslot state badly enough to permanently lock the owner
    /// out, even with the correct passphrase.
    ///
    /// This is a POSIX `fcntl` byte-range record lock on `vault.img`
    /// itself, at `header::room::LOCK_OFFSET` -- the last 4 KiB of the
    /// reserved offset gap, a region nothing else in this codebase ever
    /// reads or writes (see that constant's doc comment for why it's
    /// safe). No sibling `.lock` file: the `.img` stays the single
    /// on-disk artifact for a vault. This doesn't conflict with
    /// udisks/loop-device machinery opening the same image -- `losetup`
    /// hands the block device off to the kernel loop driver and doesn't
    /// hold a record lock on the original fd once the loop device is
    /// set up, and cryptsetup/dm-integrity operate against `/dev/loopX`,
    /// never re-acquiring a lock on the backing file. Released
    /// automatically the moment the returned guard (and the `File` it
    /// holds) drops, including on a crash or `kill -9` -- the kernel
    /// drops `fcntl` record locks when the owning process's last fd to
    /// the file closes, no explicit unlock step required.
    /// `create(true)` -- `create`'s CLI path locks before the vault image
    /// exists at all, to close the same TOCTOU race on the "already
    /// exists" check that motivated locking in the first place. That
    /// leaves a 0-byte placeholder behind when the target didn't exist
    /// yet; `commands::create::run` checks size, not mere existence, to
    /// tell that apart from a real vault (see its own comment).
    pub fn lock_exclusive(&self) -> Result<VaultLock> {
        use std::os::unix::io::AsRawFd;
        let file = std::fs::OpenOptions::new().write(true).create(true).open(&self.img)?;
        let mut fl: libc::flock = unsafe { std::mem::zeroed() };
        fl.l_type = libc::F_WRLCK as libc::c_short;
        fl.l_whence = libc::SEEK_SET as libc::c_short;
        fl.l_start = crate::header::room::LOCK_OFFSET as libc::off_t;
        fl.l_len = 4096;
        // SAFETY: `file` stays open for exactly as long as the lock is
        // held (owned by the returned guard) -- an `fcntl` record lock
        // is tied to the open file description, released when the last
        // fd referencing it closes, which `VaultLock` guarantees happens
        // no earlier than the guard's drop.
        let rc = unsafe { libc::fcntl(file.as_raw_fd(), libc::F_SETLKW, &fl) };
        if rc != 0 {
            return Err(crate::error::CasError::new(format!(
                "could not lock vault '{}': {}",
                self.name,
                std::io::Error::last_os_error()
            )));
        }
        Ok(VaultLock(file))
    }
}

/// RAII guard for `Vault::lock_exclusive` -- releases the `flock` when
/// dropped (via the held `File`'s own `Drop` closing its fd; no
/// explicit `LOCK_UN` needed, see `lock_exclusive`'s doc comment). The
/// field is never read directly -- it exists purely so its `Drop` runs
/// at the right time.
#[allow(dead_code)]
pub struct VaultLock(std::fs::File);

/// Completes an interrupted `fileIntegrity` swap if `find` would
/// otherwise report the vault as not found. The swap is two atomic
/// renames back-to-back (real -> backup, staging -> real); a crash in
/// the handful of microseconds between them leaves no file named
/// `{name}.img` at all, with the migrated container sitting right next
/// to it under its staging name. That's the only state this recovers —
/// real missing, backup AND staging both present means "step two didn't
/// run," so finishing it (staging -> real) is unambiguous.
fn recover_interrupted_migration(base: &Path, name: &str) {
    let img = base.join(format!("{name}.img"));
    let staging = base.join(format!(".{name}.fileintegrity-migration.img"));
    let backup = base.join(format!(".{name}.backup.img"));
    if !img.exists() && staging.exists() && backup.exists() {
        if std::fs::rename(&staging, &img).is_ok() {
            eprintln!(
                "{}",
                crate::color::auto(&format!(
                    "[i] completed an interrupted fileIntegrity migration for '{name}' — old container is at {}",
                    backup.display()
                ))
            );
        }
    }
}

pub fn is_mountpoint(path: &Path) -> bool {
    let Ok(meta) = std::fs::metadata(path) else {
        return false;
    };
    let Some(parent) = path.parent() else {
        return false;
    };
    let Ok(parent_meta) = std::fs::metadata(parent) else {
        return false;
    };
    if meta.dev() == parent_meta.dev() && meta.ino() == parent_meta.ino() {
        return true; // path IS its own parent (filesystem root)
    }
    meta.dev() != parent_meta.dev()
}
