// &desc: "`backup create|list|restore|delete` — manual btrfs snapshots inside an open vault."
use crate::btrfs;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::prompt;
use crate::udisks;
use crate::vault::Vault;

use super::{list_sorted, snap_root};

fn require_open(vault: &Vault) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if !vault.is_mount() {
        die!("vault is closed — open it first:  cas {} open", vault.name);
    }
    Ok(())
}

pub fn create(ctx: &Ctx, vault: &Vault, snap_name: &str) -> Result<()> {
    require_open(vault)?;
    let root = snap_root(&vault.mnt);
    if !root.exists() {
        std::fs::create_dir(&root)?;
    }
    let dest = root.join(snap_name);
    if dest.exists() {
        die!("snapshot '{snap_name}' already exists — pick a different name");
    }
    btrfs::snapshot(&vault.mnt, &dest, true)?;
    udisks::chown_to_real_user(&root)?;
    logf!(ctx, "[✓] snapshot '{snap_name}' created inside vault");
    Ok(())
}

pub fn list(ctx: &Ctx, vault: &Vault) -> Result<()> {
    require_open(vault)?;
    let meta = Meta::read(&vault.img);
    let mut manual = list_sorted(&vault.mnt, false);
    manual.reverse();
    let mut auto = list_sorted(&vault.mnt, true);
    auto.reverse();

    if manual.is_empty() && auto.is_empty() {
        logf!(ctx, "  no snapshots yet — create one with:  cas {} backup create <name>", vault.name);
        return Ok(());
    }
    if !manual.is_empty() {
        logf!(ctx, "  manual snapshots (newest first):");
        for s in &manual {
            let name = s.file_name().unwrap_or_default().to_string_lossy().into_owned();
            logf!(ctx, "    {name}  [{}]", btrfs::creation_time(s));
        }
    }
    if !auto.is_empty() {
        let keep = meta.backup_auto_keep_or(3);
        let status = if meta.backup_auto == Some(true) { "enabled" } else { "disabled" };
        logf!(ctx, "  auto-backups [{status}, keep={keep}] (newest first):");
        for s in &auto {
            let name = s.file_name().unwrap_or_default().to_string_lossy().into_owned();
            logf!(ctx, "    {name}  [{}]", btrfs::creation_time(s));
        }
    }
    Ok(())
}

pub fn restore(ctx: &Ctx, vault: &Vault, snap_name: &str) -> Result<()> {
    require_open(vault)?;
    let src = snap_root(&vault.mnt).join(snap_name);
    if !src.exists() {
        die!("snapshot '{snap_name}' not found — run 'cas {} backup list'", vault.name);
    }

    let warning = format!("All current vault contents will be replaced with snapshot '{snap_name}'.");
    if !prompt::confirm_name(ctx, &vault.name, &warning)? {
        die!("aborted");
    }

    let staging_name = format!(".cas-restore-{snap_name}");
    let staging = vault.mnt.join(&staging_name);
    btrfs::snapshot(&src, &staging, false)?;

    for entry in std::fs::read_dir(&vault.mnt)?.filter_map(|e| e.ok()) {
        let item = entry.path();
        let item_name = entry.file_name().to_string_lossy().into_owned();
        if item_name == crate::config::SNAP_DIR || item_name == staging_name {
            continue;
        }
        btrfs::delete_subvolume_silent(&item);
        if item.exists() {
            if item.is_dir() {
                let _ = std::fs::remove_dir_all(&item);
            } else {
                let _ = std::fs::remove_file(&item);
            }
        }
    }

    for entry in std::fs::read_dir(&staging)?.filter_map(|e| e.ok()) {
        let from = entry.path();
        let to = vault.mnt.join(entry.file_name());
        std::fs::rename(&from, &to)?;
    }
    btrfs::delete_subvolume_silent(&staging);

    logf!(ctx, "[✓] vault restored from snapshot '{snap_name}'");
    Ok(())
}

pub fn delete(ctx: &Ctx, vault: &Vault, snap_name: &str) -> Result<()> {
    require_open(vault)?;
    let snap = snap_root(&vault.mnt).join(snap_name);
    if !snap.exists() {
        die!("snapshot '{snap_name}' not found — run 'cas {} backup list'", vault.name);
    }
    btrfs::delete_subvolume(&snap)?;
    logf!(ctx, "[✓] snapshot '{snap_name}' deleted");
    Ok(())
}
