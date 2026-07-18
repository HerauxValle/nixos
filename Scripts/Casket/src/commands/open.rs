// &desc: "`cas <vault> open` — unlock and mount the vault, formatting it on first use and re-applying btrfs label/size housekeeping every time."
use std::path::Path;

use crate::btrfs;
use crate::commands::backup::maybe_auto_backup;
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::secret::{decode_autokey, get_secret};
use crate::udisks;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, pw: &str, kf_override: Option<&Path>) -> Result<()> {
    if vault.is_mount() {
        logf!(ctx, "[i] '{}' is already open at {}", vault.name, vault.mnt.display());
        return Ok(());
    }
    // clean up a stale mapper left behind by a crashed previous run
    if vault.mapper_dev_exists() {
        vault.close_mapper();
    }
    vault.ensure_mnt_dir()?;

    let meta = Meta::read(&vault.img);

    // Encryption UX bypass: unlock with the stored autokey, no prompt —
    // this check is unconditional (unlike get_secret's own internal
    // bypass check, which only applies when no keyfile override is
    // given), matching the original's top-level cmd_open branch exactly.
    if meta.is_encryption_bypassed() {
        let secret = decode_autokey(&meta)?;
        logf!(ctx, "[cas] opening '{}' ...", vault.name);
        return unlock_and_mount(ctx, vault, &secret, &meta);
    }

    let (secret, new_meta) = get_secret(ctx, &vault.img, pw, kf_override, Some(meta.clone()))?;
    let updated_meta = new_meta != meta;
    logf!(ctx, "[cas] opening '{}' ...", vault.name);
    unlock_and_mount(ctx, vault, &secret, &new_meta)?;
    if updated_meta {
        logf!(ctx, "  [i] updated cached keyfile path");
    }
    Ok(())
}

/// Strip the trailer, unlock via cryptsetup, restore the trailer
/// (always, even on failure), format on first use, mount, and reconcile
/// btrfs/udisks bookkeeping.
fn unlock_and_mount(ctx: &Ctx, vault: &Vault, secret: &[u8], meta: &Meta) -> Result<()> {
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

    logf!(ctx, "  [i] verifying filesystem size ...");
    btrfs::resize_silent(&vault.mnt, "max");
    btrfs::set_label(&vault.mnt, &vault.name, size_mb);
    udisks::udev_retrigger(&dev);

    udisks::chown_to_real_user(&vault.mnt)?;
    maybe_auto_backup(ctx, vault, meta);
    logf!(ctx, "[✓] '{}' is open at {}", vault.name, vault.mnt.display());
    Ok(())
}
