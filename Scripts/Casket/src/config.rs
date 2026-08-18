// &desc: "Global constants: LUKS mapper naming, the vault-file magic trailer, and the four KDF cost presets."

pub const MAPPER_PREFIX: &str = "casvault";

/// Trailing magic bytes that mark a vault's metadata block. Kept as an
/// owned array (not a `&[u8]`) so trailer comparisons are a plain array
/// `==` with no length check needed on the caller's side.
pub const MAGIC: [u8; 8] = *b"IMGVLT01";
pub const MAGIC_LEN: usize = MAGIC.len();

/// Root of `cas`'s in-vault namespace — locked as a whole by
/// ransomwareProtection, so any future protected in-vault artifact just
/// gets a subfolder here instead of a new lock target.
pub const CASKET_DIR: &str = ".casket";
pub const SNAP_DIR: &str = ".casket/snapshots";
pub const AUTO_SNAP_PREFIX: &str = "auto-";

/// Root of `cas exec`'s named rootfs environments — sibling to
/// `.casket/`, not under it, deliberately: `.casket/`'s ransomware-
/// protection lock (0700 root:root) would block path resolution into
/// anything nested beneath it, and environments need to stay user-
/// writable (installing packages, editing files) regardless of that
/// setting. Hidden (leading dot) but not protection-locked.
pub const ROOTFS_DIR: &str = ".rootfs.d";

/// Root of `cas exec`'s named custom seccomp profiles (`settings
/// security sandbox seccomp custom ...`) -- sibling to `.casket/` and
/// `.rootfs.d/`, same reasoning as `ROOTFS_DIR`: profiles are named,
/// reusable across any rootfs environment or the vault's own root
/// target, and shouldn't be nested under a directory that might not
/// exist or might be lock-protected. Named to match `.rootfs.d/`'s own
/// `.<thing>.d/` convention.
pub const SECCOMP_PROFILES_DIR: &str = ".seccomp.d";

/// LUKS2 header overhead in MiB — kept as slack between the btrfs
/// filesystem and the raw file size so cryptsetup and btrfs both stay
/// well inside the container during a resize.
pub const LUKS_OVERHEAD_MB: u64 = 32;

pub const MIN_VAULT_MB: u64 = LUKS_OVERHEAD_MB + 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strength {
    Light,
    Medium,
    Hard,
    Extreme,
}

impl Strength {
    /// `--pbkdf-memory`/`--pbkdf-parallel` pair passed to cryptsetup.
    /// `--pbkdf-parallel` is capped at 4 for every level, `Extreme`
    /// included -- confirmed live 2026-08-17 that cryptsetup 2.8.6
    /// itself refuses anything higher ("Requested maximum PBKDF
    /// parallel cost is too high (maximum is 4)"), regardless of how
    /// many CPU cores the host actually has (tested on a 16-core
    /// machine). `Extreme`'s distinguishing cost is memory + iteration
    /// count, not parallelism.
    pub const fn pbkdf_args(self) -> &'static [&'static str] {
        match self {
            Strength::Light => &["--pbkdf-memory", "128000", "--pbkdf-parallel", "2"],
            Strength::Medium => &["--pbkdf-memory", "512000", "--pbkdf-parallel", "4"],
            Strength::Hard => &["--pbkdf-memory", "1024000", "--pbkdf-parallel", "4"],
            Strength::Extreme => &["--pbkdf-memory", "2048000", "--pbkdf-parallel", "4"],
        }
    }

    pub const fn iterations(self) -> &'static str {
        match self {
            Strength::Light => "50",
            Strength::Medium => "20",
            Strength::Hard => "9",
            Strength::Extreme => "5",
        }
    }
}

impl Default for Strength {
    fn default() -> Self {
        Strength::Medium
    }
}

impl Strength {
    pub const fn as_str(self) -> &'static str {
        match self {
            Strength::Light => "light",
            Strength::Medium => "medium",
            Strength::Hard => "hard",
            Strength::Extreme => "extreme",
        }
    }
}

impl std::fmt::Display for Strength {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

impl std::str::FromStr for Strength {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "light" => Ok(Strength::Light),
            "medium" => Ok(Strength::Medium),
            "hard" => Ok(Strength::Hard),
            "extreme" => Ok(Strength::Extreme),
            other => Err(format!(
                "unknown strength '{other}' — choose: light, medium, hard, extreme"
            )),
        }
    }
}
