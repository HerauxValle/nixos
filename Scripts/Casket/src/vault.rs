// &desc: "Vault struct: resolves a vault's image/mount/mapper paths, locates one by name in cwd/ancestors, and wraps its mount-state checks."
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

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
    /// `name` must be non-empty and made up only of letters, digits,
    /// `-`, `_`, and `.` (never leading/trailing, never bare `.`/`..`) --
    /// `PathBuf::join` treats an empty string as a no-op, so an empty
    /// name previously made `mnt` resolve to `base` itself (the
    /// directory the vault lives in, or the cwd), and every command that
    /// later removed `mnt` -- most seriously `delete`'s
    /// `cleanup_mnt_dir` -- ended up removing that real directory
    /// instead of a vault-specific one. Confirmed live: `cas "" delete`
    /// deleted its own working directory. A `/` in the name has the
    /// same class of problem for the opposite reason (escapes `base`
    /// entirely), same as the rootfs-name traversal fixed in 1.10.22.
    /// The allow-list (rather than a deny-list of just the
    /// filesystem-dangerous characters) also keeps names safe to embed
    /// in external shell tooling that isn't cas itself -- see
    /// Bugs/vault-name-allows-shell-metacharacters.md.
    pub fn resolve(base: &Path, name: &str) -> Vault {
        let invalid = name.is_empty()
            || name == "."
            || name == ".."
            || name.starts_with('.')
            || name.ends_with('.')
            || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.');
        if invalid {
            eprintln!(
                "[x] invalid vault name '{name}' -- must be non-empty, can't start/end with '.', and can only contain letters, digits, '-', '_', and '.'"
            );
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
    /// out, even with the correct passphrase. Also the fix for the
    /// 2026-08-19 `bruteforceLockout` bypass -- concurrent `open`
    /// attempts against the same vault raced on the (unlocked, at the
    /// time) metadata trailer read-modify-write and silently dropped
    /// most attempts as "uncounted", see below for why the *previous*
    /// lock here didn't already prevent that.
    ///
    /// This is a whole-file `flock(LOCK_EX)` on `vault.img` itself, held
    /// via the dedicated `File` inside the returned guard -- deliberately
    /// **not** a POSIX `fcntl` byte-range record lock (what this used to
    /// be). `fcntl` locks are associated with the `(process, inode)`
    /// pair, not the file descriptor/description that acquired them --
    /// the kernel releases *all* of a process's `fcntl` locks on a file
    /// the instant *any* fd that process holds to that same inode is
    /// closed, even a completely unrelated one opened long after the
    /// lock was taken. Every command reached through this guard reopens
    /// `vault.img` repeatedly for unrelated reasons while the guard is
    /// still in scope (`Meta::strip`/`read`/`write` in `meta/mod.rs` each
    /// do their own short-lived `File::open`/`OpenOptions::open` +
    /// implicit drop) -- each one of those silently released the "held"
    /// `fcntl` lock early, long before `check_lockout`'s verify-then-
    /// increment sequence ran, which is exactly how 29/30 genuinely-wrong
    /// parallel `open` attempts got through uncounted in the confirmed
    /// repro despite this function apparently already being called for
    /// every mutating verb. `flock`, by contrast, is tied to the open
    /// file *description* (the thing `File` wraps) -- unaffected by any
    /// other fd this process opens on the same inode, and released only
    /// when this specific description's last reference (this `File`)
    /// closes. Blocking (`LOCK_EX`, no `LOCK_NB`): a legitimate
    /// concurrent command against the same vault should queue and wait
    /// its turn, not fail outright -- the only new DoS surface this adds
    /// is a slower response under heavy legitimate contention on one
    /// vault, which is what "correct" looks like for this feature (an
    /// attacker deliberately holding the lock open, e.g. via a
    /// long-running `exec`, delays but never blocks a legitimate open
    /// forever, since `exec` itself exits eventually or can be killed by
    /// the vault's owner).
    ///
    /// No byte-range/offset needed anymore since `flock` always locks the
    /// whole file -- `header::room::LOCK_OFFSET` is now unused by this
    /// function (kept as a constant in case another byte-range use shows
    /// up later; nothing else in this codebase reads/writes that region
    /// regardless).
    ///
    /// Locks a file under `/run/cas/`, NOT a sibling of `self.img` and
    /// NOT `self.img` itself.
    ///
    /// It used to flock a `<name>.img.lock` sibling of `.img` -- correct
    /// (a plain sibling file avoids both the fcntl-drops-early bug above
    /// and the cryptsetup-deadlock below), but it leaves a permanent
    /// 0-byte file sitting next to every vault image forever, since
    /// deleting it after use would reopen the same TOCTOU race locking
    /// was added to close (see below). Moving it to `/run/cas/` (tmpfs,
    /// wiped on every reboot) gets the same safety with nothing left
    /// behind on disk -- keyed by a hash of the vault's *canonicalized*
    /// parent dir + filename (not `self.img` verbatim) so two paths that
    /// resolve to the same real vault (a symlinked `base`, `../foo` vs.
    /// `foo`) still serialize against each other, and so `create` -- run
    /// before `self.img` exists -- can still compute a stable key purely
    /// from the (already-existing) parent directory.
    ///
    /// This used to flock the `.img` directly, on the (false) assumption
    /// that cryptsetup only ever touches `/dev/loopX` and never the
    /// backing file. That's wrong for the direct-file invocations this
    /// codebase actually uses (`cryptsetup luksFormat ... vault.img`,
    /// no `losetup` in between): cryptsetup takes its own internal
    /// `flock(LOCK_EX)` on that same file as part of its own concurrency
    /// safety. Holding our lock across a shelled-out `cryptsetup` call
    /// against the same fd-by-inode self-deadlocked every command that
    /// both locks and shells to cryptsetup (`create`, `open`, `resize`,
    /// `auth passwd`, `settings encryption enable`, ...) -- confirmed
    /// live via strace: our process holds the flock, `cryptsetup
    /// luksFormat` blocks forever re-acquiring it on its own fd. A
    /// dedicated lock file (whether a sibling or, now, under `/run/cas/`)
    /// sidesteps this entirely since cryptsetup never opens it.
    ///
    /// `create(true)` -- `create`'s CLI path locks before the vault image
    /// exists at all, to close the same TOCTOU race on the "already
    /// exists" check that motivated locking in the first place. Since the
    /// lock file is keyed off the parent directory (always present) and
    /// never the image itself, `create` needs no 0-byte image placeholder
    /// for this -- `vault.img.exists()` alone is enough.
    /// Stable identifier for `/run/cas/` lock files: SHA-256 of the
    /// vault's canonicalized parent directory joined with its image
    /// filename. Canonicalizing only the parent (not `self.img`) means
    /// this works even when `self.img` doesn't exist yet (`create`'s
    /// whole reason for locking in the first place) -- `base` (the
    /// directory a vault lives in) always exists by the time any command
    /// resolves a `Vault`. Falls back to the parent as given, uncanon-
    /// icalized, if it can't be resolved (e.g. removed mid-race) rather
    /// than failing the lock outright -- worst case two different-looking
    /// paths to the same vault get separate locks, no worse than the old
    /// sibling-file scheme ever guaranteed.
    fn lock_key(&self) -> String {
        let parent = self.img.parent().unwrap_or(Path::new("."));
        let resolved = std::fs::canonicalize(parent).unwrap_or_else(|_| parent.to_path_buf());
        let key_path = resolved.join(self.img.file_name().unwrap_or_default());
        let mut hasher = Sha256::new();
        hasher.update(key_path.to_string_lossy().as_bytes());
        format!("{:x}", hasher.finalize())
    }

    pub fn lock_exclusive(&self) -> Result<VaultLock> {
        use std::os::unix::io::AsRawFd;
        let lock_dir = Path::new("/run/cas");
        std::fs::create_dir_all(lock_dir)?;
        let lock_path = lock_dir.join(format!("{}.lock", self.lock_key()));
        let file = std::fs::OpenOptions::new().write(true).create(true).open(&lock_path)?;
        // SAFETY: `file` stays open for exactly as long as the lock is
        // held (owned by the returned guard) -- `flock` releases the
        // lock when this file description's last reference closes, which
        // `VaultLock` guarantees happens no earlier than the guard's
        // drop, including on a crash or `kill -9` (the kernel always
        // closes fds of a dead process, releasing any `flock`s with
        // them).
        let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) };
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
pub struct VaultLock(std::fs::File);

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
