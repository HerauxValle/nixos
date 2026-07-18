// &desc: "Shared snapshot-path helpers, the post-open auto-backup hook, and the `backup <sub>` dispatch routing to manual.rs and auto.rs."
pub mod auto;
pub mod manual;

use std::path::{Path, PathBuf};

use crate::btrfs;
use crate::config::{AUTO_SNAP_PREFIX, SNAP_DIR};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::vault::Vault;

pub fn snap_root(mnt: &Path) -> PathBuf {
    mnt.join(SNAP_DIR)
}

/// Snapshot subdirectories under `mnt`'s snapshot root, filtered by
/// whether their name has the `auto-` prefix, oldest first.
pub fn list_sorted(mnt: &Path, auto: bool) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(snap_root(mnt)) else {
        return Vec::new();
    };
    let mut snaps: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .filter(|p| {
            let is_auto = p
                .file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.starts_with(AUTO_SNAP_PREFIX));
            is_auto == auto
        })
        .collect();
    snaps.sort_by_key(|p| p.metadata().and_then(|m| m.modified()).ok());
    snaps
}

fn ensure_dir(path: &Path) -> bool {
    match std::fs::create_dir(path) {
        Ok(()) => true,
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => true,
        Err(_) => false,
    }
}

fn prune_auto(ctx: &Ctx, mnt: &Path, keep: u32) {
    let auto_snaps = list_sorted(mnt, true);
    let excess = auto_snaps.len().saturating_sub(keep as usize);
    for snap in auto_snaps.into_iter().take(excess) {
        let name = snap.file_name().unwrap_or_default().to_string_lossy().into_owned();
        match btrfs::delete_subvolume(&snap) {
            Ok(()) => logf!(ctx, "  [i] auto-backup pruned: {name}"),
            Err(e) => logf!(ctx, "  [!] could not prune auto-backup '{name}': {e}"),
        }
    }
}

/// Called after every successful `open`: creates a timestamped read-only
/// snapshot if `backup_auto` is set in metadata, then prunes down to the
/// configured keep count. Best-effort — a failure here (e.g. the mount
/// directory isn't writable yet) never fails the `open` it's attached to.
pub fn maybe_auto_backup(ctx: &Ctx, vault: &Vault, meta: &Meta) {
    if meta.backup_auto != Some(true) {
        return;
    }
    let keep = meta.backup_auto_keep_or(3);
    let root = snap_root(&vault.mnt);
    if !ensure_dir(&root) {
        return;
    }
    let snap_name = btrfs::format_auto_snap_name(btrfs::now_secs());
    let dest = root.join(&snap_name);
    match btrfs::snapshot(&vault.mnt, &dest, true) {
        Ok(()) => logf!(ctx, "  [i] auto-backup created: {snap_name}"),
        Err(e) => {
            logf!(ctx, "  [!] auto-backup failed: {e}");
            return;
        }
    }
    prune_auto(ctx, &vault.mnt, keep);
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String]) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("create") => match extra.get(1) {
            Some(name) => manual::create(ctx, vault, name),
            None => die!("usage: cas <vault> backup create <name>\n    Example:  cas myvault backup create before-upgrade"),
        },
        Some("list") => manual::list(ctx, vault),
        Some("restore") => match extra.get(1) {
            Some(name) => manual::restore(ctx, vault, name),
            None => die!("usage: cas <vault> backup restore <name>\n    Example:  cas myvault backup restore before-upgrade"),
        },
        Some("delete") => match extra.get(1) {
            Some(name) => manual::delete(ctx, vault, name),
            None => die!("usage: cas <vault> backup delete <name>\n    Example:  cas myvault backup delete old-snap"),
        },
        Some("auto") => auto::dispatch(ctx, vault, &extra[1..]),
        _ => die!("usage: cas <vault> backup create|list|restore|delete|auto\n    Run 'cas help backup' for details."),
    }
}
