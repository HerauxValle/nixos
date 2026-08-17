// &desc: "Reads/writes the vault's trailing metadata block: [JSON][4-byte BE length][8-byte magic], appended after the LUKS container — byte-compatible with the Python original. Missing/renamed fields go through crate::migrations so a `cas` update never breaks reading an older vault; an unreadable-but-present trailer is backed up rather than silently discarded."
use std::collections::BTreeMap;
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::config::{MAGIC, MAGIC_LEN};

/// Fixed part of the trailer: the 4-byte length prefix plus the magic.
const TRAILER_FIXED_LEN: i64 = MAGIC_LEN as i64 + 4;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Meta {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub keyfile: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub encrypted: Option<bool>,
    #[serde(rename = "_autokey", skip_serializing_if = "Option::is_none")]
    pub autokey: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backup_auto: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backup_auto_keep: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ransomware_protection: Option<bool>,
    /// Whether the resolved passphrase and derived LUKS secret get
    /// scrubbed from memory the moment they go out of scope. `None`
    /// means the default (on) applies -- see `secret::zeroize_enabled`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zeroize: Option<bool>,
    /// Per-feature override of whether `cas <vault> settings ...` toggles
    /// require re-proving the passphrase first. Absent entries fall back
    /// to `commands::settings::gate`'s built-in defaults.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verify_required: Option<BTreeMap<String, bool>>,
    /// HMAC-SHA256 (hex) over `tamper::protected_json(self)`, keyed by
    /// the vault's own derived secret -- see `tamper.rs`. `None` means
    /// no verified write has happened yet (a fresh vault, or one from
    /// before this field existed); that's "unprotected", not "tampered".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub meta_hmac: Option<String>,
    /// How many consecutive wrong-passphrase `open` attempts since the
    /// last success. Only consulted/incremented when `bruteforceLockout`
    /// is enabled -- see `settings/security/bruteforce_lockout.rs`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failed_attempts: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bruteforce_lockout: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bruteforce_threshold: Option<u32>,
    /// Whether the container is currently dm-integrity-protected
    /// (per-sector authenticated encryption) — set by
    /// `settings security fileIntegrity`'s migration, never toggled any
    /// other way (it reflects the actual on-disk container format).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_integrity: Option<bool>,
    /// Whether `cas <vault> exec` is permitted at all — see
    /// `commands::settings::security::sandbox`. `namespaces`/`cgroups`/
    /// `seccomp`/`rootfs` sub-settings are only meaningful once this is on.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_enabled: Option<bool>,
    /// Active Linux namespaces for `exec` (`mount`/`pid`/`uts`/`ipc`/
    /// `user`/`net`). `user` is always included regardless of this list —
    /// see `sandbox::namespaces`. `None` means the built-in default
    /// (everything except `net`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_namespaces: Option<Vec<String>>,
    /// Per-target seccomp setting, keyed by rootfs name (or `"_root"`
    /// for the no-named-rootfs fallback case `exec` uses when
    /// `.rootfs.d/` has zero entries) -- either a built-in preset name
    /// (`default`/`strict`/`none`/`compute`) or a named custom profile
    /// under `.seccomp.d/`, both from the same flat namespace (no
    /// prefix distinguishes them, see `commands::settings::security::
    /// sandbox::seccomp::set`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_seccomp: Option<BTreeMap<String, String>>,
    /// SHA-256 (hex) of each named custom seccomp profile's `.seccomp.d/
    /// <name>.toml` file at the time it was last saved via `seccomp
    /// custom edit`/`create` — detects a profile being edited outside
    /// that verified path. Keyed by profile name (not target key, since
    /// one profile can be referenced by several targets at once).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_seccomp_profile_hash: Option<BTreeMap<String, String>>,
    /// Cgroup resource limits for `exec` sessions — memory (e.g.
    /// `"512M"`), CPU percent, max PIDs. Not tamper-HMAC-covered:
    /// resource limits, not an attacker-facing protection toggle (same
    /// category as `backup_auto`/`backup_auto_keep`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_cgroup_mem: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_cgroup_cpu: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_cgroup_pids: Option<u32>,
    /// Rootfs environment names additionally snapshotted by `backup
    /// create`/`backupAuto`, on top of the vault's own top-level
    /// content. `.casket/` is never includable — no field for it exists.
    /// Default (absent/empty) = none included.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox_backup_rootfs: Option<Vec<String>>,
    /// Whether the 32 MiB header-hiding "room" (see `header::room`) has
    /// been provisioned in the slack space between the LUKS2 container
    /// and this trailer. Set once, lazily, on first `enable` of either
    /// `headerOffset`/`headerEncryption` -- never unset (the room stays
    /// even if both toggles are later disabled, so re-enabling doesn't
    /// have to reprovision).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub header_room: Option<bool>,
    /// Whether the LUKS2 header currently lives at a passphrase-derived
    /// slot inside the room instead of the container's front. See
    /// `header::relocate`. Tamper-HMAC-covered and re-derived from
    /// physical ground truth on tamper detection, not trusted blindly.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub header_offset: Option<bool>,
    /// Whether the header's content (wherever it currently lives -- the
    /// front, or a room slot) is ChaCha20-Poly1305-encrypted rather than
    /// a plain cryptsetup-native header. See `header::relocate`. Same
    /// tamper-HMAC/ground-truth treatment as `header_offset`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub header_encryption: Option<bool>,
}

/// Find the trailer on an open handle. Returns `(payload_start_offset,
/// payload_len)` from the start of the file, or `None` if the file is too
/// short or the trailing 8 bytes don't match `MAGIC` — an untagged image.
fn locate(f: &mut File) -> Option<(u64, u32)> {
    let file_len = f.metadata().ok()?.len();
    if file_len < MAGIC_LEN as u64 {
        return None;
    }
    let mut magic_buf = [0u8; MAGIC_LEN];
    f.seek(SeekFrom::End(-(MAGIC_LEN as i64))).ok()?;
    f.read_exact(&mut magic_buf).ok()?;
    if magic_buf != MAGIC {
        return None;
    }
    if file_len < TRAILER_FIXED_LEN as u64 {
        return None;
    }
    let mut len_buf = [0u8; 4];
    f.seek(SeekFrom::End(-TRAILER_FIXED_LEN)).ok()?;
    f.read_exact(&mut len_buf).ok()?;
    let size = u32::from_be_bytes(len_buf);
    let payload_start = (file_len as i64) - TRAILER_FIXED_LEN - size as i64;
    if payload_start < 0 {
        return None;
    }
    Some((payload_start as u64, size))
}

/// Byte offset where the trailer (if any) begins — i.e. the end of the
/// LUKS2 container + any reserved room ahead of the trailer. `None` if
/// the file has no trailer at all. Exposed read-only for `header::room`,
/// which needs to find where its 32 MiB room sits (immediately before
/// this offset) without duplicating `locate`'s parsing logic or
/// changing it.
pub fn trailer_start(img: &Path) -> Option<u64> {
    let mut f = File::open(img).ok()?;
    locate(&mut f).map(|(start, _)| start)
}

impl Meta {
    /// Read the trailing metadata block. No trailer at all (a fresh or
    /// never-tagged vault) is legitimately "no metadata" and defaults
    /// silently. A trailer that *is* present but fails to parse or
    /// migrate is a different case — never treated the same way, since a
    /// later `write()` would then permanently overwrite real keyfile /
    /// encryption / settings data with nothing. See `recover_unreadable`.
    pub fn read(img: &Path) -> Meta {
        Self::read_versioned(img).0
    }

    /// Same as `read`, but also returns the schema version the trailer
    /// was written at *before* migrating (0 for an untagged/fresh
    /// vault, or the current version if there was nothing to read) —
    /// `open` needs that number to know which `crate::migrations` layout
    /// steps a newly-mounted vault is still owed, which can only run
    /// once the vault's filesystem is reachable.
    pub fn read_versioned(img: &Path) -> (Meta, u64) {
        let mut f = match File::open(img) {
            Ok(f) => f,
            Err(_) => return (Meta::default(), crate::version::CURRENT),
        };
        let Some((start, size)) = locate(&mut f) else {
            return (Meta::default(), crate::version::CURRENT);
        };
        let mut buf = vec![0u8; size as usize];
        if f.seek(SeekFrom::Start(start)).is_err() || f.read_exact(&mut buf).is_err() {
            return (Meta::default(), crate::version::CURRENT);
        }
        drop(f);

        let Some(raw) = serde_json::from_slice::<serde_json::Value>(&buf).ok() else {
            recover_unreadable(img, &buf);
            return (Meta::default(), crate::version::CURRENT);
        };
        let from = raw.get("_v").and_then(serde_json::Value::as_u64).unwrap_or(0);
        match serde_json::from_value(crate::migrations::migrate_meta(raw, from)) {
            Ok(meta) => (meta, from),
            Err(_) => {
                recover_unreadable(img, &buf);
                (Meta::default(), crate::version::CURRENT)
            }
        }
    }

    /// Truncate away an existing trailer, if present. No-op if the file
    /// can't be opened or carries no trailer. Must run before any LUKS
    /// operation — cryptsetup treats the whole file as a raw block device
    /// and would otherwise see the trailer as part of its own data.
    pub fn strip(img: &Path) -> std::io::Result<()> {
        let mut f = match OpenOptions::new().read(true).write(true).open(img) {
            Ok(f) => f,
            Err(_) => return Ok(()),
        };
        if let Some((start, _)) = locate(&mut f) {
            f.set_len(start)?;
        }
        Ok(())
    }

    /// Strip any existing trailer, then append this metadata as the new
    /// one. Always stripping first means repeated writes never stack.
    pub fn write(&self, img: &Path) -> std::io::Result<()> {
        Self::strip(img)?;
        let mut value = serde_json::to_value(self).unwrap_or_default();
        if let serde_json::Value::Object(ref mut map) = value {
            map.insert("_v".to_string(), serde_json::Value::from(crate::version::CURRENT));
        }
        let payload = serde_json::to_vec(&value).unwrap_or_default();
        let mut f = OpenOptions::new().append(true).open(img)?;
        f.write_all(&payload)?;
        f.write_all(&(payload.len() as u32).to_be_bytes())?;
        f.write_all(&MAGIC)?;
        Ok(())
    }

    pub fn has_2fa(&self) -> bool {
        self.keyfile.is_some()
    }

    pub fn is_encryption_bypassed(&self) -> bool {
        self.encrypted == Some(false) && self.autokey.is_some()
    }

    pub fn backup_auto_keep_or(&self, default: u32) -> u32 {
        self.backup_auto_keep.unwrap_or(default)
    }
}

/// A trailer was found but couldn't be turned into a `Meta` — corruption
/// or a migration bug, not a fresh vault. Preserve the raw bytes next to
/// the image (skipping if a backup from a previous read already exists,
/// so this doesn't rewrite it on every command) and say so loudly on
/// stderr regardless of --no-log. Never blocks the command that
/// triggered it — the vault stays usable with defaults.
fn recover_unreadable(img: &Path, raw: &[u8]) {
    let backup = img.with_extension("meta.corrupt");
    if !backup.exists() && std::fs::write(&backup, raw).is_err() {
        eprintln!(
            "{}",
            crate::color::auto(&format!(
                "[!] '{}' has an unreadable metadata trailer and the recovery backup could not be written",
                img.display()
            ))
        );
        return;
    }
    eprintln!(
        "{}",
        crate::color::auto(&format!(
            "[!] '{}' has an unreadable metadata trailer -- raw bytes preserved at {}",
            img.display(),
            backup.display()
        ))
    );
    eprintln!("    continuing with default settings; the vault's encrypted data is untouched");
}
