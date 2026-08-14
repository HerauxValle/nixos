// &desc: "`cas <vault> settings security fileIntegrity enable|disable [--delete-backup]` — migrates the vault to (or off of) a dm-integrity-protected LUKS2 container, so a corrupted or tampered byte anywhere in the vault's actual files gets detected instead of silently decrypting to garbage. Not a plain Feature.set toggle: both directions run the same copy-verify-swap migration (config.rs's Strength choice aside, only the destination luksFormat's --integrity flag differs), so it's dispatched directly rather than through registry::dispatch."
use std::ffi::CString;
use std::fs;
use std::path::Path;

use crate::btrfs;
use crate::commands::settings::gate::gate_pw;
use crate::config::{MIN_VAULT_MB, LUKS_OVERHEAD_MB};
use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::migrate;
use crate::secret::{combined_secret, resolve_keyfile};
use crate::udisks;
use crate::vault::Vault;

pub fn is_enabled(meta: &Meta) -> bool {
    meta.file_integrity == Some(true)
}

fn migration_vault(vault: &Vault) -> Vault {
    Vault::resolve(vault.base(), &format!(".{}.fileintegrity-migration", vault.name))
}

fn backup_vault(vault: &Vault) -> Vault {
    Vault::resolve(vault.base(), &format!(".{}.backup", vault.name))
}

fn free_mb(dir: &Path) -> Option<u64> {
    let c = CString::new(dir.to_string_lossy().into_owned()).ok()?;
    unsafe {
        let mut buf: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(c.as_ptr(), &mut buf) != 0 {
            return None;
        }
        Some((buf.f_bavail as u64 * buf.f_frsize as u64) / (1024 * 1024))
    }
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => {
            let delete_backup = extra.iter().any(|a| a == "--delete-backup");
            run(ctx, vault, true, delete_backup, pw)
        }
        Some("disable") => {
            let delete_backup = extra.iter().any(|a| a == "--delete-backup");
            run(ctx, vault, false, delete_backup, pw)
        }
        Some("state") => {
            let meta = Meta::read(&vault.img);
            logf!(ctx, "{}", crate::commands::settings::registry::line("fileIntegrity", is_enabled(&meta), crate::commands::settings::registry::column_width(&["fileIntegrity"])));
            Ok(())
        }
        _ => die!("usage: cas <vault> settings security fileIntegrity enable|disable [--delete-backup] | state"),
    }
}

fn run(ctx: &Ctx, vault: &Vault, enable: bool, delete_backup: bool, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if !vault.is_mount() {
        die!("vault must be open first:  cas {} open", vault.name);
    }
    let meta = Meta::read(&vault.img);
    if is_enabled(&meta) == enable {
        let word = if enable { "enabled" } else { "disabled" };
        die!("fileIntegrity is already {word} for '{}'", vault.name);
    }

    let pw = gate_pw(ctx, vault, "fileIntegrity", pw)?;
    let secret = match meta.keyfile.clone() {
        Some(cached) => {
            let mut m = meta.clone();
            let kf_path = resolve_keyfile(ctx, &cached, &mut m, &vault.img)?;
            combined_secret(&pw, &crate::keyfile::read_bytes(&kf_path)?)
        }
        None => pw.as_bytes().to_vec(),
    };
    if !luks::test(&vault.img, &secret) {
        die!("wrong passphrase — could not verify vault");
    }

    let staging = migration_vault(vault);
    let backup = backup_vault(vault);
    let size_mb = vault.img.metadata()?.len() / (1024 * 1024);

    let host_free = free_mb(vault.base()).unwrap_or(0);
    if host_free < size_mb {
        die!(
            "not enough free space on the host to migrate — need ~{size_mb} MiB free alongside the vault, found {host_free} MiB\n    ({}, migration needs old + new to coexist until it's verified)",
            vault.base().display()
        );
    }

    let action = if enable { "enabling" } else { "disabling" };
    logf!(ctx, "[cas] {action} fileIntegrity for '{}' ...", vault.name);

    // Clean up a stale staging mapper left behind by a crashed previous
    // attempt — same as `open`'s own stale-mapper cleanup. Without this,
    // resuming after a kill -9 mid-migration fails immediately: the
    // mapper name is still held by the dead process's mapping, and
    // cryptsetup refuses to open a second one under the same name.
    if staging.mapper_dev_exists() {
        staging.umount();
        staging.close_mapper();
    }

    // Resume: a staging container from a previous interrupted attempt
    // that still opens with this secret, and is still the right size,
    // is treated as a valid partial copy, not started over. One that
    // doesn't open (crash mid-format) — or one sized for a vault that's
    // since been resized, which can never have enough room no matter
    // how many times a resize+retry is tried, since a stale staging
    // file never grows on its own — gets replaced instead.
    let staging_size_matches = staging.img.metadata().map(|m| m.len() / (1024 * 1024) == size_mb).unwrap_or(false);
    let resuming = staging.img.exists() && staging_size_matches && luks::test(&staging.img, &secret);
    if staging.img.exists() && !resuming {
        if !staging_size_matches {
            logf!(ctx, "  [i] discarding a leftover migration staged for a different vault size — starting fresh");
        }
        let _ = fs::remove_file(&staging.img);
    }
    if !staging.img.exists() {
        fs::File::create(&staging.img)?;
        let img_str = staging.img.to_string_lossy().into_owned();
        crate::proc::run("truncate", &["-s", &format!("{size_mb}M"), &img_str])?;
        luks::format_vault_ex(&staging.img, &secret, Strength::default(), enable)?;
        let mut staging_meta = meta.clone();
        staging_meta.file_integrity = enable.then_some(true);
        staging_meta.write(&staging.img)?;
    } else {
        logf!(ctx, "  [i] resuming a previous interrupted migration");
    }

    let result = migrate_body(ctx, vault, &staging, &secret, size_mb);

    // Always tear down the staging mount/mapper before returning,
    // success or failure — never leave it mounted for the caller to
    // trip over. Unmount first: cryptsetup refuses to close a mapper
    // that's still mounted, and close_mapper()'s failure is silent, so
    // skipping the unmount here would leave the mapper (and the swap
    // below acting on a still-open container) silently wrong instead of
    // erroring.
    staging.umount();
    staging.close_mapper();
    staging.cleanup_mnt_dir();

    result?;

    // Real vault must actually be unmounted (not just have its mapper
    // "closed," which silently no-ops while still mounted) before the
    // swap — otherwise the rename below happens under an active mount,
    // and whoever's using the vault keeps seeing the *old* container
    // under the old mapper, invisibly detached from the file that now
    // has its name.
    vault.umount_checked()?;
    vault.close_mapper_checked()?;

    // Swap: overwrite a leftover backup name from a prior interrupted
    // attempt, then two atomic renames.
    if backup.img.exists() {
        fs::remove_file(&backup.img)?;
    }
    fs::rename(&vault.img, &backup.img)?;
    fs::rename(&staging.img, &vault.img)?;

    if delete_backup {
        fs::remove_file(&backup.img)?;
        logf!(ctx, "[✓] fileIntegrity {} for '{}' — old container deleted (--delete-backup)", if enable { "enabled" } else { "disabled" }, vault.name);
    } else {
        let backup_mb = backup.img.metadata().map(|m| m.len() / (1024 * 1024)).unwrap_or(0);
        logf!(ctx, "[✓] fileIntegrity {} for '{}'", if enable { "enabled" } else { "disabled" }, vault.name);
        logf!(ctx, "  [i] old container preserved at {} (~{backup_mb} MiB) — delete it yourself once you've confirmed the migrated vault opens correctly:", backup.img.display());
        logf!(ctx, "      rm '{}'", backup.img.display());
    }
    logf!(ctx, "    the vault is now closed — open it again:  cas {} open", vault.name);
    Ok(())
}

fn migrate_body(ctx: &Ctx, vault: &Vault, staging: &Vault, secret: &[u8], size_mb: u64) -> Result<()> {
    let dev = luks::open_luks(&staging.img, &staging.mapper, secret)?;
    staging.ensure_mnt_dir()?;
    if !btrfs::blkid_output(&dev).contains("btrfs") {
        btrfs::mkfs(&dev, &staging.name, size_mb)?;
    }
    staging.mount(&dev)?;

    // Usable capacity after integrity's per-sector tags/journal overhead
    // can be meaningfully smaller than the raw container size — same
    // 110%-of-used safety margin `resize`'s shrink path already uses.
    if let Some(used_mb) = btrfs::used_mb(&vault.mnt) {
        let staging_free_mb = free_mb(&staging.mnt).unwrap_or(0);
        let min_needed = (used_mb as f64 * 1.10) as u64 + 1;
        if staging_free_mb < min_needed {
            let suggested = size_mb + (min_needed.saturating_sub(staging_free_mb)) + LUKS_OVERHEAD_MB;
            die!(
                "not enough room in the new container after integrity overhead — needs ~{min_needed} MiB, has ~{staging_free_mb} MiB\n    try:  cas {} resize {}M   (then re-run this command)",
                vault.name, suggested.max(MIN_VAULT_MB)
            );
        }
    }

    migrate::copy_tree(ctx, &vault.mnt, &staging.mnt)?;
    migrate::verify_tree(ctx, &vault.mnt, &staging.mnt)?;

    udisks::chown_to_vault_owner(&staging.mnt, &staging.img)?;
    Ok(())
}
