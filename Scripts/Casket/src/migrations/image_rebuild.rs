// &desc: "The `requires_new_image` migration path: build a brand-new vault image with current-build params (right now, just `config::LUKS_DATA_OFFSET_MB`), copy every real file across from the currently-opened old image, verify byte-for-byte, then atomically swap it into the vault's own path. Same stage -> copy -> verify -> swap shape as `commands::settings::security::file_integrity`'s container migration (that function is the template this one follows), generalized to run from `open.rs` before a vault becomes usable at all, gated by an explicit confirm prompt there."
use std::fs;

use crate::btrfs;
use crate::config::{Strength, LUKS_OVERHEAD_MB, MIN_VAULT_MB};
use crate::ctx::Ctx;
use crate::error::{CasError, Result};
use crate::header;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::migrate;
use crate::tamper;
use crate::udisks;
use crate::vault::Vault;

fn staging_vault(vault: &Vault) -> Vault {
    Vault::resolve(vault.base(), &format!(".{}.image-rebuild", vault.name))
}

fn backup_vault(vault: &Vault) -> Vault {
    Vault::resolve(vault.base(), &format!(".{}.pre-rebuild.backup", vault.name))
}

fn free_mb(dir: &std::path::Path) -> Option<u64> {
    let c = std::ffi::CString::new(dir.to_string_lossy().into_owned()).ok()?;
    unsafe {
        let mut buf: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(c.as_ptr(), &mut buf) != 0 {
            return None;
        }
        Some((buf.f_bavail as u64 * buf.f_frsize as u64) / (1024 * 1024))
    }
}

/// Reset exactly the settings this particular rebuild reason unlocks (or
/// invalidates) to their default/unconfigured state, per the user's
/// explicit directive: a migration that adds a new capability turns it
/// available, not auto-enabled. `header_offset`/`header_encryption`/
/// `header_room`/`header_room_slots` are the ones affected here -- the
/// old image's relocated-header room (wherever it lived) has no meaning
/// against a freshly-formatted image with a different data offset, so
/// carrying those fields forward unmodified would leave `meta` claiming
/// a relocation that was never actually redone on the new container.
/// Everything else (file_integrity, ransomware/backup/sandbox settings,
/// the cached keyfile path, etc.) is a real, still-accurate description
/// of the vault's data and carries forward unchanged.
fn reset_unlocked_capabilities(meta: &mut Meta) {
    meta.header_offset = None;
    meta.header_encryption = None;
    meta.header_room = None;
    meta.header_room_slots = None;
}

/// Rebuild `vault`'s image in place with current-build format params,
/// preserving every real file. `vault` must already be confirmed
/// unlocked by `secret` (caller's job -- this trusts it without
/// re-verifying) and must NOT be mounted yet; this function does the
/// open/copy/verify/swap itself and leaves the vault closed again on
/// success, exactly like `open.rs`'s caller expects so the normal
/// `unlock_and_mount` path can run immediately after against the new
/// (already-current-schema) image.
pub fn rebuild(ctx: &Ctx, vault: &Vault, meta: &Meta, secret: &[u8]) -> Result<()> {
    let staging = staging_vault(vault);
    let backup = backup_vault(vault);

    if staging.mapper_dev_exists() {
        staging.umount();
        staging.close_mapper();
    }

    // The old image is opened/mounted here under the vault's own real
    // mapper name (via the normal detached-or-native dispatch, same as
    // a real `open` would) so `migrate::copy_tree` has a real mountpoint
    // to read from -- this function runs *instead of* `open`'s own
    // unlock_and_mount for this one call, not alongside it.
    if vault.mapper_dev_exists() {
        vault.close_mapper();
    }
    vault.ensure_mnt_dir()?;
    header::relocate::resume_scrub_if_pending(&vault.img);
    let old_dev = if header::relocate::is_native_front(meta) {
        luks::open_luks(&vault.img, &vault.mapper, secret)?
    } else {
        let salt = match meta.header_room_slots {
            Some(n) => header::room::v3_read_salt(&vault.img, n as u64),
            None => header::room::read_salt(&vault.img),
        }
        .ok_or_else(|| CasError::new("vault metadata says the header is relocated/encrypted, but no header room was found"))?;
        let master = header::derive_master_secret(&[secret], &salt);
        let staged = header::relocate::stage_current_header(vault, meta, Some(&master))?;
        luks::open_luks_detached(staged.path(), &vault.img, &vault.mapper, secret)?
    };
    crate::proc::run_silent("udevadm", &["settle", "--timeout=5"]);
    if !btrfs::blkid_output(&old_dev).contains("btrfs") {
        vault.close_mapper();
        return Err(CasError::new("old image has no filesystem yet — nothing to migrate; open it normally first"));
    }
    vault.mount(&old_dev)?;

    let result = rebuild_body(ctx, vault, &staging, meta, secret);

    vault.umount();
    vault.close_mapper();
    staging.umount();
    staging.close_mapper();
    staging.cleanup_mnt_dir();

    result?;

    // Deliberately not `vault.cleanup_mnt_dir()` -- the caller (`open.rs`)
    // still needs `vault.mnt` to exist right after this returns, for its
    // own normal `unlock_and_mount` against the now-swapped-in new image.

    if backup.img.exists() {
        fs::remove_file(&backup.img)?;
    }
    fs::rename(&vault.img, &backup.img)?;
    fs::rename(&staging.img, &vault.img)?;

    logf!(ctx, "  [i] rebuild complete — old container preserved at {} (~{} MiB); delete it yourself once you've confirmed the vault opens and looks right:", backup.img.display(), backup.img.metadata().map(|m| m.len() / (1024 * 1024)).unwrap_or(0));
    logf!(ctx, "      rm '{}'", backup.img.display());
    Ok(())
}

fn rebuild_body(ctx: &Ctx, vault: &Vault, staging: &Vault, meta: &Meta, secret: &[u8]) -> Result<()> {
    let size_mb = vault.img.metadata()?.len() / (1024 * 1024);
    let host_free = free_mb(vault.base()).unwrap_or(0);
    if host_free < size_mb {
        return Err(CasError::new(format!(
            "not enough free space on the host to rebuild — need ~{size_mb} MiB free alongside the vault, found {host_free} MiB (old + new must coexist until verified)"
        )));
    }

    let integrity = luks::has_integrity(&vault.img);

    let staging_size_matches = staging.img.metadata().map(|m| m.len() / (1024 * 1024) == size_mb).unwrap_or(false);
    let resuming = staging.img.exists() && staging_size_matches && luks::test(&staging.img, secret);
    if staging.img.exists() && !resuming {
        let _ = fs::remove_file(&staging.img);
    }
    if !staging.img.exists() {
        fs::File::create(&staging.img)?;
        let img_str = staging.img.to_string_lossy().into_owned();
        crate::proc::run("truncate", &["-s", &format!("{size_mb}M"), &img_str])?;
        // Same param this build's `create`/`fileIntegrity` migration
        // uses -- `Strength` isn't tracked in `Meta` (it's baked only
        // into the LUKS2 keyslot, unrecoverable after format), so a
        // rebuild can't reproduce the vault's original KDF cost preset
        // exactly and uses the current default, same simplification
        // `fileIntegrity`'s migration already makes.
        luks::format_vault_ex(&staging.img, secret, Strength::default(), integrity)?;
        let mut staging_meta = meta.clone();
        // No explicit version field to set here -- `Meta::write` always
        // stamps the trailer's `_v` as `version::CURRENT` itself, and a
        // freshly-formatted image has no old trailer to migrate away
        // from, so this write already lands at the current schema.
        reset_unlocked_capabilities(&mut staging_meta);
        tamper::refresh(secret, &mut staging_meta);
        staging_meta.write(&staging.img)?;
    } else {
        logf!(ctx, "  [i] resuming a previous interrupted rebuild");
    }

    let dev = luks::open_luks(&staging.img, &staging.mapper, secret)?;
    staging.ensure_mnt_dir()?;
    if !btrfs::blkid_output(&dev).contains("btrfs") {
        btrfs::mkfs(&dev, &staging.name, size_mb)?;
    }
    staging.mount(&dev)?;

    if let Some(used_mb) = btrfs::used_mb(&vault.mnt) {
        let staging_free_mb = free_mb(&staging.mnt).unwrap_or(0);
        let min_needed = (used_mb as f64 * 1.10) as u64 + 1;
        if staging_free_mb < min_needed {
            let suggested = size_mb + (min_needed.saturating_sub(staging_free_mb)) + LUKS_OVERHEAD_MB;
            return Err(CasError::new(format!(
                "not enough room in the rebuilt container — needs ~{min_needed} MiB, has ~{staging_free_mb} MiB\n    try:  cas {} resize {}M   (then re-run open)",
                vault.name, suggested.max(MIN_VAULT_MB)
            )));
        }
    }

    migrate::copy_tree(ctx, &vault.mnt, &staging.mnt)?;
    migrate::verify_tree(ctx, &vault.mnt, &staging.mnt)?;
    udisks::chown_to_vault_owner(&staging.mnt, &staging.img)?;
    Ok(())
}
