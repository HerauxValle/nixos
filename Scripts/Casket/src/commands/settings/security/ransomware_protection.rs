// &desc: "`cas <vault> settings security ransomwareProtection enable|disable` — locks .casket/ to root-only so a process running as the vault's own user (e.g. ransomware) can't read, create, or delete anything cas keeps inside the mounted filesystem."
use std::fs::Permissions;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry::Feature;
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::udisks;
use crate::vault::Vault;

pub const FEATURE: Feature = Feature {
    name: "ransomwareProtection",
    set,
    get: is_enabled,
};

pub fn is_enabled(meta: &Meta) -> bool {
    meta.ransomware_protection == Some(true)
}

/// Bring `.casket/`'s ownership in line with the current policy:
/// root-only (700, root:root) when protection is on, handed back to the
/// real user for direct browsing when it's off. Called on toggle, on
/// every open (drift correction), and whenever the directory is created.
pub fn apply_ownership(casket_dir: &Path, meta: &Meta) -> Result<()> {
    if is_enabled(meta) {
        // Locking just the root is enough — without execute permission
        // on `.casket/` itself, the kernel denies path resolution into
        // anything beneath it, whatever that content's own perms are.
        std::os::unix::fs::chown(casket_dir, Some(0), Some(0))?;
        std::fs::set_permissions(casket_dir, Permissions::from_mode(0o700))?;
    } else {
        // Not symmetric: category folders like `snapshots/` are created
        // directly by root (e.g. `create_dir_all` on first auto-backup)
        // and were never chowned themselves, so handing back access
        // means reaching one level in, not just the root. Never
        // recurses into a snapshot's own contents — read-only btrfs
        // subvolumes reject chown anyway, and deleting one only needs
        // write permission on its parent, not on itself.
        std::fs::set_permissions(casket_dir, Permissions::from_mode(0o755))?;
        udisks::chown_to_real_user(casket_dir)?;
        if let Ok(entries) = std::fs::read_dir(casket_dir) {
            for entry in entries.filter_map(|e| e.ok()) {
                if entry.path().is_dir() {
                    let _ = udisks::chown_to_real_user(&entry.path());
                }
            }
        }
    }
    Ok(())
}

pub fn set(ctx: &Ctx, vault: &Vault, enable: bool, pw: Option<&str>) -> Result<()> {
    // If verification is currently required for this feature, gate_inner
    // resolves+checks the real passphrase and hands back its derived
    // secret, which also refreshes this field's tamper-evidence HMAC
    // (tamper.rs). If verification is off, nothing is prompted or
    // checked — same as before tamper-evidence existed — and the HMAC
    // is simply left as whatever it was.
    let verified = gate_inner(ctx, vault, "ransomwareProtection", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.ransomware_protection = enable.then_some(true);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;

    if vault.is_mount() {
        let casket_dir = vault.casket_dir();
        if casket_dir.exists() {
            apply_ownership(&casket_dir, &meta)?;
        }
    }

    if enable {
        logf!(ctx, "[✓] ransomware protection enabled for '{}'", vault.name);
        logf!(ctx, "    .casket/ is now root-only — your user account can no longer read, create, or delete anything in it");
    } else {
        logf!(ctx, "[✓] ransomware protection disabled for '{}'", vault.name);
        logf!(ctx, "    .casket/ is owned by you again");
    }
    Ok(())
}

/// Called after every successful open: re-applies the current ownership
/// policy so drift, or a toggle made while the vault was closed, is
/// corrected immediately rather than waiting for the next snapshot.
pub fn enforce_on_open(ctx: &Ctx, vault: &Vault, meta: &Meta) {
    let casket_dir = vault.casket_dir();
    if !casket_dir.exists() {
        return;
    }
    if apply_ownership(&casket_dir, meta).is_err() {
        logf!(ctx, "  [!] could not re-apply .casket/ ownership policy");
    }
}
