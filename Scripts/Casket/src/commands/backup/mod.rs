// &desc: "Shared snapshot-path helpers, the post-open auto-backup hook, and the `backup <sub>` dispatch routing to manual.rs -- data operations only; the auto-backup on/off policy itself lives at settings::backup_auto since it's a persistent setting, not a data operation."
pub mod manual;
pub mod rootfs;

use std::path::{Path, PathBuf};

use crate::btrfs;
use crate::commands::settings::security::ransomware_protection;
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

/// Ensures `.casket/` exists as a real btrfs subvolume before anything
/// creates content under it. The v2 schema migration converts an
/// *existing* plain-directory `.casket/` (every vault created before
/// the sandbox feature) -- but a brand-new vault's `.casket/` was still
/// getting first-created as a plain directory here (via `create_dir_
/// all` on first backup), never as a subvolume, silently defeating the
/// "a vault snapshot never includes .casket/" guarantee the whole
/// rootfs-backup-inclusion design depends on. Idempotent, same as
/// `rootfs::ensure_dir`'s pattern for `.rootfs.d/`.
fn ensure_casket_subvolume(vault: &Vault) -> Result<()> {
    let dir = vault.casket_dir();
    if !dir.exists() {
        btrfs::subvolume_create(&dir)?;
    }
    Ok(())
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

/// Reflink-copies each rootfs environment named in `meta.sandbox_
/// backup_rootfs` into `dest/.rootfs.d/<name>`, alongside a snapshot
/// already taken of `vault.mnt` itself. A plain snapshot of the vault's
/// mount already skips `.rootfs.d/` entirely for free (it's a real
/// btrfs subvolume, and subvolume snapshots don't descend into nested
/// subvolumes) -- this is what opts specific environments back in.
/// `dest` must still be writable when this runs (see call sites: the
/// main snapshot is taken read-write, this populates it, then it's
/// flipped read-only) -- an individual `<name>` directory isn't itself
/// a subvolume, only `.rootfs.d/` as a whole is, so `btrfs subvolume
/// snapshot` can't target it directly; a reflink copy is the practical
/// equivalent. Best-effort per environment: one failing doesn't block
/// the others or the main snapshot.
fn snapshot_included_rootfs(ctx: &Ctx, vault: &Vault, meta: &Meta, dest: &Path) {
    let Some(names) = &meta.sandbox_backup_rootfs else {
        return;
    };
    if names.is_empty() {
        return;
    }
    // Deliberately NOT `dest.join(config::ROOTFS_DIR)`: that exact path,
    // inside a snapshot, is where the vault's own `.rootfs.d` subvolume
    // boundary used to be -- btrfs keeps it as a protected placeholder
    // even after snapshotting (confirmed empirically: mkdir there fails
    // EPERM, as root, even on an otherwise-writable snapshot). A
    // differently-named path sidesteps the collision entirely.
    let dest_root = dest.join(".casket-included-rootfs");
    if std::fs::create_dir_all(&dest_root).is_err() {
        logf!(ctx, "  [!] could not create {} for included rootfs snapshots", dest_root.display());
        return;
    }
    for name in names {
        let src = vault.rootfs_dir().join(name);
        if !src.exists() {
            continue; // included by name, but no longer exists -- nothing to snapshot
        }
        // `.rootfs.d/<name>/` is a plain directory, not a subvolume
        // itself (only `.rootfs.d/` as a whole is) -- `btrfs subvolume
        // snapshot` requires a subvolume source, so a reflink copy is
        // used instead. Still a cheap CoW copy on btrfs, just without a
        // snapshot's atomic point-in-time guarantee across the whole
        // tree -- an acceptable tradeoff for a mostly-static rootfs.
        let dst = dest_root.join(name);
        if std::fs::create_dir_all(&dst).is_err() {
            logf!(ctx, "  [!] could not create {} for included rootfs '{name}'", dst.display());
            continue;
        }
        let src_glob = format!("{}/.", src.display());
        match crate::proc::run("cp", &["-a", "--reflink=auto", &src_glob, &dst.to_string_lossy()]) {
            Ok(()) => logf!(ctx, "  [i] included rootfs '{name}' copied into backup"),
            Err(e) => logf!(ctx, "  [!] could not copy included rootfs '{name}' into backup: {e}"),
        }
    }
}

fn ensure_dir(path: &Path) -> bool {
    match std::fs::create_dir_all(path) {
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
    if ensure_casket_subvolume(vault).is_err() {
        return;
    }
    let root = snap_root(&vault.mnt);
    if !ensure_dir(&root) {
        return;
    }
    let _ = ransomware_protection::apply_ownership(&vault.casket_dir(), meta);
    let snap_name = btrfs::format_auto_snap_name(btrfs::now_secs());
    let dest = root.join(&snap_name);
    // Writable first -- included rootfs copies (below) need to write
    // into `dest`, which a snapshot taken read-only from the start
    // would refuse. Flipped read-only afterward, once populated.
    match btrfs::snapshot(&vault.mnt, &dest, false) {
        Ok(()) => logf!(ctx, "  [i] auto-backup created: {snap_name}"),
        Err(e) => {
            logf!(ctx, "  [!] auto-backup failed: {e}");
            return;
        }
    }
    snapshot_included_rootfs(ctx, vault, meta, &dest);
    if let Err(e) = btrfs::set_readonly(&dest, true) {
        logf!(ctx, "  [!] could not mark auto-backup '{snap_name}' read-only: {e}");
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
        Some("auto") => die!(
            "the auto-backup on/off policy moved: cas <vault> settings backup auto enable|disable|keep <N>"
        ),
        Some("rootfs") => rootfs::dispatch(ctx, vault, &extra[1..]),
        _ => die!("usage: cas <vault> backup create|list|restore|delete|rootfs\n    Run 'cas help backup' for details."),
    }
}
