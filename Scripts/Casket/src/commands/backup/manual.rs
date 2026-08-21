// &desc: "`backup create|list|restore|delete` — manual btrfs snapshots inside an open vault."
use crate::btrfs;
use crate::commands::settings::security::ransomware_protection;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::prompt;
use crate::vault::Vault;

use super::{list_sorted, snap_root, snapshot_included_rootfs};

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
    crate::name::validate("snapshot", snap_name)?;
    super::ensure_casket_subvolume(vault)?;
    let root = snap_root(&vault.mnt);
    if !root.exists() {
        std::fs::create_dir_all(&root)?;
    }
    let dest = root.join(snap_name);
    if dest.exists() {
        die!("snapshot '{snap_name}' already exists — pick a different name");
    }
    // Writable first -- see backup::maybe_auto_backup's identical
    // comment: included rootfs copies need to write into `dest` before
    // it's flipped read-only.
    btrfs::snapshot(&vault.mnt, &dest, false)?;
    let meta = Meta::read(&vault.img);
    snapshot_included_rootfs(ctx, vault, &meta, &dest);
    btrfs::set_readonly(&dest, true)?;
    ransomware_protection::apply_ownership(&vault.casket_dir(), &meta)?;
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
        let is_enabled = meta.backup_auto == Some(true);
        let status = crate::color::state(is_enabled, if is_enabled { "enabled" } else { "disabled" });
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
    crate::name::validate("snapshot", snap_name)?;
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

    // NOT `std::fs::rename` -- `staging` is its own btrfs subvolume
    // (created by `btrfs::snapshot` above), and the kernel refuses to
    // `rename()` anything across a subvolume boundary on btrfs
    // (`EXDEV`/"Invalid cross-device link"), even though both
    // subvolumes live on the very same physical filesystem. Confirmed
    // empirically: every restore failed here, after the loop above had
    // already deleted the vault's live contents -- real data loss. `cp
    // --reflink=always` is the standard btrfs-safe way to move content
    // between subvolumes of the same filesystem: it's a real copy (so
    // no EXDEV), but a copy-on-write one (so no actual block
    // duplication or meaningful time cost) as long as source and dest
    // share a filesystem, which they always do here.
    for entry in std::fs::read_dir(&staging)?.filter_map(|e| e.ok()) {
        let from = entry.path();
        let to = vault.mnt.join(entry.file_name());
        let from_s = from.to_string_lossy().into_owned();
        let to_s = to.to_string_lossy().into_owned();
        crate::proc::run("cp", &["--reflink=always", "-a", "--", &from_s, &to_s])?;
    }
    btrfs::delete_subvolume_silent(&staging);

    logf!(ctx, "[✓] vault restored from snapshot '{snap_name}'");
    Ok(())
}

pub fn delete(ctx: &Ctx, vault: &Vault, snap_name: &str) -> Result<()> {
    require_open(vault)?;
    crate::name::validate("snapshot", snap_name)?;
    let snap = snap_root(&vault.mnt).join(snap_name);
    if !snap.exists() {
        die!("snapshot '{snap_name}' not found — run 'cas {} backup list'", vault.name);
    }
    btrfs::delete_subvolume(&snap)?;
    logf!(ctx, "[✓] snapshot '{snap_name}' deleted");
    Ok(())
}
