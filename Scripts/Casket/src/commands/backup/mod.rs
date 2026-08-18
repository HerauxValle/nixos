// &desc: "Shared snapshot-path helpers, the post-open auto-backup hook, and the registry-driven `backup <sub>` dispatch -- data operations only; the auto-backup on/off policy itself lives at settings::backup_auto since it's a persistent setting, not a data operation. dispatch() resolves the whole `backup` subtree (create/list/restore/delete plus every `rootfs` leaf) in one shot via cli_registry::resolve, same pattern as commands::settings::security::sandbox::network / commands::auth."
pub mod manual;
pub mod rootfs;

use std::path::{Path, PathBuf};

use crate::cli_registry::Domain;
use crate::btrfs;
use crate::cli_registry::{self, Resolved};
use crate::commands::settings::security::ransomware_protection;
use crate::config::{AUTO_SNAP_PREFIX, SNAP_DIR};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::vault::Vault;

/// This subtree's own flat, position-independent id space -- see
/// `cli/registry.kdl`'s doc comment and `src/cli_registry/mod.rs`'s for
/// the full reasoning. Each variant is a bare number, not a semantic
/// name: the meaningful name lives on the handler function it maps to
/// below, never on the id itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code1110,
    Code1111,
    Code1112,
    Code1113,
    Code1114,
    Code1115,
    Code1116,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[
        ("1110", ActionId::Code1110),
        ("1111", ActionId::Code1111),
        ("1112", ActionId::Code1112),
        ("1113", ActionId::Code1113),
        ("1114", ActionId::Code1114),
        ("1115", ActionId::Code1115),
        ("1116", ActionId::Code1116),
    ];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    /// Every code this domain knows how to handle -- consulted only by
    /// `cas debug parse-cli` (via the domain's `known_ids` export) to
    /// compute the Ignored list, never by dispatch itself.
    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Finds the `backup` node inside the compiled-in registry tree once.
/// If this ever returns `None` it means `cli/registry.kdl` and this
/// file's hardcoded navigation path have drifted apart -- a build-
/// time/test bug, not something a user can trigger.
fn backup_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| cli_registry::get().vault.iter().find(|n| n.name == "backup").map(|n| n.children.clone()).unwrap_or_default())
        .as_slice()
}

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
    if extra.first().map(String::as_str) == Some("auto") {
        die!("the auto-backup on/off policy moved: cas <vault> settings backup auto enable|disable|keep <N>");
    }
    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(backup_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..])
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> backup create|list|restore|delete|rootfs\n    Run 'cas help backup' for details.")
        }
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, rest: &[String]) -> Result<()> {
    match id {
        ActionId::Code1110 => match rest.first() {
            Some(name) => manual::create(ctx, vault, name),
            None => die!("usage: cas <vault> backup create <name>\n    Example:  cas myvault backup create before-upgrade"),
        },
        ActionId::Code1111 => manual::list(ctx, vault),
        ActionId::Code1112 => match rest.first() {
            Some(name) => manual::restore(ctx, vault, name),
            None => die!("usage: cas <vault> backup restore <name>\n    Example:  cas myvault backup restore before-upgrade"),
        },
        ActionId::Code1113 => match rest.first() {
            Some(name) => manual::delete(ctx, vault, name),
            None => die!("usage: cas <vault> backup delete <name>\n    Example:  cas myvault backup delete old-snap"),
        },
        ActionId::Code1114 => rootfs::set(ctx, vault, rest.first(), true),
        ActionId::Code1115 => rootfs::set(ctx, vault, rest.first(), false),
        ActionId::Code1116 => rootfs::state(ctx, vault),
    }
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation -- see
/// `commands::debug`.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }
