// &desc: "`cas <vault> open` — unlock and mount the vault, formatting it on first use and re-applying btrfs label/size housekeeping every time."
use std::path::Path;

use crate::btrfs;
use crate::commands::backup::maybe_auto_backup;
use crate::commands::settings::security::{bruteforce_lockout, ransomware_protection};
use crate::ctx::Ctx;
use crate::error::{CasError, Result};
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::migrations;
use crate::secret::{decode_autokey, get_secret};
use crate::tamper;
use crate::udisks;
use crate::vault::Vault;

/// If `bruteforceLockout` is on, test the passphrase *before* the real
/// unlock attempt so a wrong guess is unambiguous (not confused with an
/// unrelated open failure — a busy mapper looks identical to a bad
/// passphrase from `open_luks`'s error alone). A correct guess resets
/// the counter; a wrong one increments it and, past the threshold,
/// deletes the vault with no confirmation — that's the point of turning
/// this on. Returns `Err` (aborting the open) exactly when it deleted
/// the vault or the passphrase was wrong; `Ok(false)` means proceed.
fn check_lockout(ctx: &Ctx, vault: &Vault, secret: &[u8], meta: &mut Meta) -> Result<bool> {
    if !bruteforce_lockout::is_enabled(meta) {
        return Ok(false);
    }
    Meta::strip(&vault.img)?;
    let ok = luks::test(&vault.img, secret);
    meta.write(&vault.img)?;

    if ok {
        if meta.failed_attempts.is_some() {
            meta.failed_attempts = None;
            meta.write(&vault.img)?;
        }
        return Ok(false);
    }

    let attempts = meta.failed_attempts.unwrap_or(0) + 1;
    let threshold = bruteforce_lockout::threshold(meta);
    if attempts >= threshold {
        let _ = std::fs::remove_file(&vault.img);
        vault.cleanup_mnt_dir();
        logf!(ctx, "[x] '{}' deleted — {threshold} consecutive wrong-passphrase attempts reached (bruteforceLockout)", vault.name);
        return Err(CasError::Silent);
    }
    meta.failed_attempts = Some(attempts);
    meta.write(&vault.img)?;
    logf!(ctx, "  [!] wrong passphrase ({attempts}/{threshold} — vault deletes at {threshold})");
    Err(CasError::Silent)
}

/// Check the metadata HMAC now that the real secret is known, and if it
/// doesn't match, throw away the 3 protected fields' current values
/// (they're exactly what's suspect) and fall back to the maximally
/// protective setting for each instead — never a silent downgrade. The
/// open still proceeds; refusing to open would risk locking the owner
/// out over a false positive (a migration bug, a hand edit made before
/// this feature existed) with no way back in.
fn check_tamper(ctx: &Ctx, vault: &Vault, secret: &[u8], meta: &mut Meta) {
    if tamper::verify(secret, meta) == tamper::Status::Tampered {
        logf!(ctx, "  [!] '{}' metadata failed its tamper check — ransomwareProtection/verify_required/zeroize don't match what was last written with a verified passphrase", vault.name);
        logf!(ctx, "      resetting those 3 settings to their most-protective values; review with 'cas {} info' and adjust as needed", vault.name);
        tamper::reset_to_safe(meta);
    }
}

pub fn run(
    ctx: &Ctx,
    vault: &Vault,
    pw: &str,
    kf_override: Option<&Path>,
    kf_cache_hint: Option<&Path>,
) -> Result<()> {
    if vault.is_mount() {
        logf!(ctx, "[i] '{}' is already open at {}", vault.name, vault.mnt.display());
        return Ok(());
    }
    // clean up a stale mapper left behind by a crashed previous run
    if vault.mapper_dev_exists() {
        vault.close_mapper();
    }
    vault.ensure_mnt_dir()?;

    let (mut meta, schema_from) = Meta::read_versioned(&vault.img);

    // Encryption UX bypass: unlock with the stored autokey, no prompt —
    // this check is unconditional (unlike get_secret's own internal
    // bypass check, which only applies when no keyfile override is
    // given), matching the original's top-level cmd_open branch exactly.
    if meta.is_encryption_bypassed() {
        let secret = decode_autokey(&meta)?;
        check_tamper(ctx, vault, &secret, &mut meta);
        logf!(ctx, "[cas] opening '{}' ...", vault.name);
        return unlock_and_mount(ctx, vault, &secret, &meta, schema_from);
    }

    let (secret, mut new_meta) =
        get_secret(ctx, &vault.img, pw, kf_override, kf_cache_hint, Some(meta.clone()))?;
    check_lockout(ctx, vault, &secret, &mut new_meta)?;
    check_tamper(ctx, vault, &secret, &mut new_meta);
    let updated_meta = new_meta != meta;
    logf!(ctx, "[cas] opening '{}' ...", vault.name);
    unlock_and_mount(ctx, vault, &secret, &new_meta, schema_from)?;
    if updated_meta {
        logf!(ctx, "  [i] updated cached keyfile path");
    }
    Ok(())
}

/// Strip the trailer, unlock via cryptsetup, restore the trailer
/// (always, even on failure), format on first use, mount, and reconcile
/// btrfs/udisks bookkeeping.
fn unlock_and_mount(ctx: &Ctx, vault: &Vault, secret: &[u8], meta: &Meta, schema_from: u64) -> Result<()> {
    Meta::strip(&vault.img)?;
    let dev = match luks::open_luks(&vault.img, &vault.mapper, secret) {
        Ok(d) => d,
        Err(e) => {
            meta.write(&vault.img)?;
            return Err(e);
        }
    };
    meta.write(&vault.img)?;

    let size_mb = vault.img.metadata()?.len() / (1024 * 1024);
    if !btrfs::blkid_output(&dev).contains("btrfs") {
        logf!(ctx, "  [i] first open — formatting filesystem ...");
        btrfs::mkfs(&dev, &vault.name, size_mb)?;
    }
    vault.mount(&dev)?;

    // Layout migrations need the mounted filesystem, so they can only
    // run here — before anything else (auto-backup, ransomware lock
    // enforcement) touches whatever they're renaming/restructuring.
    migrations::migrate_layout(ctx, vault, schema_from);

    logf!(ctx, "  [i] verifying filesystem size ...");
    btrfs::resize_silent(&vault.mnt, "max");
    btrfs::set_label(&vault.mnt, &vault.name, size_mb);
    udisks::udev_retrigger(&dev);

    udisks::chown_to_vault_owner(&vault.mnt, &vault.img)?;
    maybe_auto_backup(ctx, vault, meta);
    ransomware_protection::enforce_on_open(ctx, vault, meta);
    logf!(ctx, "[✓] '{}' is open at {}", vault.name, vault.mnt.display());
    Ok(())
}
