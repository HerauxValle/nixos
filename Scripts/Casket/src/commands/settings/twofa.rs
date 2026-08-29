// &desc: "`cas <vault> settings 2fa enable|disable` — generate/remove the 2FA keyfile and re-key the vault to/from a passphrase+keyfile combined secret. Already self-verifies via the real passphrase in on()/off(), so `gate()` is a no-op unless verification is explicitly turned on for this feature too."
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;

use crate::commands::settings::gate::gate_pw;
use crate::commands::settings::registry::Feature;
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::header::relocate;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::secret::{b64_encode, combined_secret, get_secret, resolve_keyfile};
use crate::udisks;
use crate::vault::Vault;

/// Cycle `img`'s LUKS keyslot from `old_secret` to `new_secret`, pointed
/// at the header wherever it actually lives (front, or `headerOffset`'s
/// room slot) — mirrors `passwd.rs`'s identical branch, needed here too
/// since 2FA on/off is exactly as much a "rotate the LUKS secret" event
/// as a passphrase change is.
fn cycle_secret(ctx: &Ctx, vault: &Vault, meta: &Meta, old_secret: &[u8], new_secret: &[u8]) -> Result<()> {
    // Not just offset_enabled -- headerEncryption alone also means the
    // container's front bytes aren't a directly-testable plain LUKS2
    // header anymore (they're AEAD ciphertext), so plain slot_cycle
    // against the raw front fails just as surely as it would under
    // headerOffset. is_native_front covers all three "something's
    // relocated and/or encrypted" states with one check. Confirmed live
    // 2026-08-17: 2fa enable under headerEncryption-alone failed with
    // "current passphrase did not match any LUKS slot" before this fix.
    if !relocate::is_native_front(meta) {
        let salt = crate::header::room::read_salt(&vault.img)
            .ok_or_else(|| CasError::new("header room not found — vault metadata is inconsistent"))?;
        let master = crate::header::derive_master_secret(&[old_secret], &salt);
        let staged = relocate::stage_current_header(vault, meta, Some(&master))?;
        luks::slot_cycle_detached(ctx, staged.path(), &vault.img, old_secret, new_secret, None)
    } else {
        luks::slot_cycle(ctx, &vault.img, old_secret, new_secret, None)
    }
}

pub const FEATURE: Feature = Feature { name: "2fa", set, get: |meta| meta.has_2fa() };

fn set(ctx: &Ctx, vault: &Vault, enable: bool, pw: Option<&str>) -> Result<()> {
    let pw = gate_pw(ctx, vault, "2fa", pw)?;
    if enable {
        on(ctx, vault, &pw)
    } else {
        off(ctx, vault, &pw)
    }
}

fn on(ctx: &Ctx, vault: &Vault, pw: &str) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let meta = Meta::read(&vault.img);
    if meta.keyfile.is_some() {
        die!("2FA is already enabled\n    Run 'cas {} settings 2fa disable' first.", vault.name);
    }

    // Respects the encryption=off autokey shortcut the same way `open`
    // does — no prompt needed if the vault is already unlocked-by-default.
    let (old_secret, _) = get_secret(ctx, &vault.img, pw, None, false, None, Some(meta.clone()))?;

    let kf_path = vault.base().join(format!("{}.key", vault.name));
    let mut key_bytes = [0u8; 64];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut key_bytes);
    {
        // Created with 0600 from the first syscall — no separate chmod,
        // so there's no window where the key sits at default umask perms.
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&kf_path)?;
        f.write_all(&key_bytes)?;
    }
    udisks::chown_to_real_user(&kf_path)?;
    logf!(ctx, "  [i] generated keyfile: {}", kf_path.display());
    logf!(ctx, "      Back this up — losing it means losing access to the vault.");

    let new_secret = combined_secret(pw, &key_bytes);
    logf!(ctx, "[cas] enabling 2FA on '{}' ...", vault.name);
    Meta::strip(&vault.img)?;

    // Start from a clone of the existing Meta, not Meta::default() --
    // building fresh and manually carrying over a handful of fields
    // (the old approach) silently drops every field someone forgets to
    // list by hand on the next new setting: confirmed live 2026-08-17,
    // `file_integrity` was reset to `None` (shown as "disabled" by
    // `info`) on the very next 2FA toggle after being set at creation,
    // even though the container's real on-disk dm-integrity layout
    // never changed. Only the fields that must actually differ for a
    // 2FA-enable are overwritten below.
    let mut new_meta = meta.clone();
    new_meta.keyfile = Some(kf_path.to_string_lossy().into_owned());
    new_meta.autokey = None;
    if meta.encrypted == Some(false) {
        new_meta.encrypted = Some(false);
        new_meta.autokey = Some(b64_encode(&new_secret));
    }

    if let Err(e) = cycle_secret(ctx, vault, &meta, &old_secret, &new_secret) {
        meta.write(&vault.img)?;
        let _ = std::fs::remove_file(&kf_path);
        return Err(e);
    }

    if let Err(e) = relocate::relocate_if_enabled(ctx, vault, &mut new_meta, &old_secret, &new_secret, None) {
        meta.write(&vault.img)?;
        let _ = std::fs::remove_file(&kf_path);
        return Err(e);
    }

    new_meta.write(&vault.img)?;
    logf!(ctx, "[✓] 2FA enabled — keyfile: {}", kf_path.display());
    logf!(ctx, "    You now need BOTH your passphrase AND that keyfile to open this vault.");
    Ok(())
}

fn off(ctx: &Ctx, vault: &Vault, pw: &str) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let mut meta = Meta::read(&vault.img);
    if meta.keyfile.is_none() {
        die!("2FA is not enabled on this vault");
    }
    let cached = meta.keyfile.clone().unwrap();
    let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img, crate::version::CURRENT)?;
    let kf_bytes = crate::keyfile::read_bytes(&kf_path)?;
    let old_secret = combined_secret(pw, &kf_bytes);
    let new_secret = pw.as_bytes().to_vec();

    logf!(ctx, "[cas] disabling 2FA on '{}' ...", vault.name);
    Meta::strip(&vault.img)?;

    // Same reasoning as `on()` -- clone rather than rebuild from
    // Meta::default() so every existing setting survives the toggle.
    let mut new_meta = meta.clone();
    new_meta.keyfile = None;
    new_meta.autokey = None;
    if meta.encrypted == Some(false) {
        new_meta.encrypted = Some(false);
        new_meta.autokey = Some(b64_encode(&new_secret));
    }

    if let Err(e) = cycle_secret(ctx, vault, &meta, &old_secret, &new_secret) {
        meta.write(&vault.img)?;
        return Err(e);
    }

    if let Err(e) = relocate::relocate_if_enabled(ctx, vault, &mut new_meta, &old_secret, &new_secret, None) {
        meta.write(&vault.img)?;
        return Err(e);
    }

    std::fs::remove_file(&kf_path)?;
    new_meta.write(&vault.img)?;
    logf!(ctx, "[✓] 2FA disabled — passphrase alone is sufficient again");
    logf!(ctx, "  [i] keyfile deleted: {}", kf_path.display());
    Ok(())
}
