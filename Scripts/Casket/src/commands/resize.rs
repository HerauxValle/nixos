// &desc: "`cas <vault> resize <size>` — grow instantly or shrink with a used-space safety check, restoring the metadata trailer on every exit path including failure."
use std::path::Path;

use crate::btrfs;
use crate::config::{LUKS_OVERHEAD_MB, MIN_VAULT_MB};
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::proc;
use crate::prompt;
use crate::secret::get_secret;
use crate::udisks;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, new_mb: u64, pw: &str) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let current_mb = vault.img.metadata()?.len() / (1024 * 1024);
    let shrink = new_mb < current_mb;

    if new_mb < MIN_VAULT_MB {
        die!("minimum vault size is {MIN_VAULT_MB} MiB");
    }

    let meta = Meta::read(&vault.img);
    let (secret, meta) = get_secret(ctx, &vault.img, pw, None, Some(meta))?;
    vault.close_mapper(); // clear a stale mapper from a previous crashed resize
    Meta::strip(&vault.img)?;

    let mut mounted_tmp = false;
    let result = body(ctx, vault, new_mb, current_mb, shrink, &secret, &mut mounted_tmp);

    // Unwind exactly like the original's `finally` — but *also* always
    // restore the metadata trailer. The Python version only wrote it
    // back on the success path: a die() during the shrink safety check
    // (or any failure after meta_strip) left the trailer stripped for
    // good, silently losing the vault's 2FA/backup_auto settings even
    // though the LUKS data itself was untouched.
    if mounted_tmp {
        vault.umount();
    }
    vault.close_mapper();
    vault.cleanup_mnt_dir();
    meta.write(&vault.img)?;

    result?;

    udisks::refresh_size(&vault.img);
    let action_word = if shrink { "shrunk" } else { "resized" };
    logf!(ctx, "[✓] '{}' {action_word} to {new_mb} MiB", vault.name);
    Ok(())
}

fn body(
    ctx: &Ctx,
    vault: &Vault,
    new_mb: u64,
    current_mb: u64,
    shrink: bool,
    secret: &[u8],
    mounted_tmp: &mut bool,
) -> Result<()> {
    let dev = luks::open_luks(&vault.img, &vault.mapper, secret)?;
    vault.ensure_mnt_dir()?;
    let luks_mb = new_mb.saturating_sub(LUKS_OVERHEAD_MB);

    if shrink {
        let has_fs = btrfs::blkid_output(&dev).contains("TYPE=");
        if has_fs {
            vault
                .mount(&dev)
                .map_err(|e| CasError::new(format!("could not mount vault to check used space\n    {e}")))?;
            *mounted_tmp = true;
            match btrfs::used_mb(&vault.mnt) {
                Some(used_mb) => {
                    let min_mb = (used_mb as f64 * 1.10) as u64 + 1 + LUKS_OVERHEAD_MB;
                    if new_mb < min_mb {
                        die!(
                            "too small — vault contains ~{used_mb} MiB of data\n    minimum safe size is {min_mb} MiB (110% of used + overhead)\n    try:  cas {} resize {min_mb}M",
                            vault.name
                        );
                    }
                }
                None => logf!(ctx, "  [!] could not read used space — proceeding without safety check"),
            }
        } else {
            logf!(ctx, "  [i] vault has never been opened — no filesystem to check");
        }

        let warning = format!("WARNING: shrinking from {current_mb} to {new_mb} MiB");
        if !prompt::confirm_name(ctx, &vault.name, &warning)? {
            die!("aborted — name did not match");
        }

        logf!(ctx, "[cas] shrinking '{}' {current_mb} -> {new_mb} MiB ...", vault.name);
        if has_fs && *mounted_tmp {
            btrfs::resize(&vault.mnt, &format!("{luks_mb}m"))?;
            btrfs::set_label(&vault.mnt, &vault.name, new_mb);
            vault.umount_checked()?;
            *mounted_tmp = false;
        }
        luks::resize(&vault.mapper, secret, Some(luks_mb * 2048))?;
        let img_str = vault.img.to_string_lossy().into_owned();
        proc::run("truncate", &["-s", &format!("{new_mb}M"), &img_str])?;
    } else {
        if new_mb == current_mb {
            die!("vault is already {current_mb} MiB");
        }
        logf!(ctx, "[cas] resizing '{}' {current_mb} -> {new_mb} MiB ...", vault.name);
        let img_str = vault.img.to_string_lossy().into_owned();
        proc::run("truncate", &["-s", &format!("{new_mb}M"), &img_str])?;
        luks::resize(&vault.mapper, secret, None)?;
        if vault.is_mount() {
            btrfs::resize(&vault.mnt, "max")?;
        }
    }

    btrfs::set_label(Path::new(&dev), &vault.name, new_mb);
    udisks::udev_retrigger(&dev);
    Ok(())
}
