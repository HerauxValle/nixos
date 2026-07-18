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
    pub fn resolve(base: &Path, name: &str) -> Vault {
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
        }
        die!(
            "vault '{name}' not found (searched cwd and 4 levels up)\n    Hint: run 'cas list' to see all vaults, or cd to where it lives."
        );
    }

    pub fn base(&self) -> &Path {
        self.img.parent().unwrap_or(Path::new("."))
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
