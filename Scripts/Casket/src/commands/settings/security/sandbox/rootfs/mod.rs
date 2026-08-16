// &desc: "`cas <vault> settings security sandbox rootfs list|add|update|remove|rename|default` -- named rootfs environments for `exec --rootfs <name>`. `.rootfs.d/` is created lazily as a real btrfs subvolume the first time any rootfs subcommand runs, not by a migration -- most vaults never use this feature, so nothing about it should touch a vault that doesn't opt in."
use std::fs;
use std::path::PathBuf;

mod add;
mod default;
mod remove;
mod rename;
mod update;

use crate::btrfs;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::udisks;
use crate::vault::Vault;

/// Reserved across every rootfs subcommand that takes a name -- `all`
/// is the `--removeRootfs`/`remove` wildcard keyword (never a glob, to
/// avoid shell expansion surprises), `default` would collide with the
/// `default` verb/symlink itself.
pub const RESERVED_NAMES: &[&str] = &["all", "default"];

const DEFAULT_SYMLINK: &str = "default";

/// Ensures `.rootfs.d/` exists as a real subvolume (creating it, chowned
/// to the real user, on first call) and returns its path. Idempotent --
/// a no-op once it's already there. `.rootfs.d/` deliberately isn't
/// subject to ransomwareProtection's lock (see `Vault::rootfs_dir`'s doc
/// comment), so it's chowned to the real user unconditionally, not
/// gated on that setting the way `.casket/` is.
pub fn ensure_dir(vault: &Vault) -> Result<PathBuf> {
    let dir = vault.rootfs_dir();
    if !dir.exists() {
        btrfs::subvolume_create(&dir)?;
        udisks::chown_to_real_user(&dir)?;
    }
    Ok(dir)
}

/// The current `default` environment's name, or `None` if unset,
/// dangling (points at something that no longer exists), or -- the
/// security-relevant case -- resolves outside `.rootfs.d/` entirely.
/// The symlink's target is plain user/attacker-writable filesystem
/// state feeding directly into what `exec` later pivot_roots into, so
/// it's canonicalized and containment-checked here, once, rather than
/// trusted at every call site.
pub fn default_target(vault: &Vault) -> Option<String> {
    let dir = vault.rootfs_dir();
    let link = dir.join(DEFAULT_SYMLINK);
    let resolved = fs::canonicalize(&link).ok()?;
    let dir_canon = fs::canonicalize(&dir).ok()?;
    if resolved.parent() != Some(dir_canon.as_path()) {
        return None; // escapes .rootfs.d/ -- treat exactly like "unset"
    }
    resolved.file_name()?.to_str().map(str::to_string)
}

/// Sets (`Some(name)`) or clears (`None`) the `default` symlink. A
/// plain filesystem symlink, not a metadata field -- `ln -sfn` inside
/// the mounted vault would do the same thing by hand.
pub fn set_default(vault: &Vault, name: Option<&str>) -> Result<()> {
    let dir = ensure_dir(vault)?;
    let link = dir.join(DEFAULT_SYMLINK);
    let _ = fs::remove_file(&link);
    if let Some(name) = name {
        std::os::unix::fs::symlink(name, &link)?;
    }
    Ok(())
}

/// Which rootfs environment (if any) a caller should use, per the one
/// resolution rule shared by `exec --rootfs` and `seccomp --rootfs`: an
/// explicit `<name>` always wins; otherwise zero environments means
/// `Ok(None)` (isolate the vault's own content directly / target the
/// `_root` sentinel), exactly one is used automatically, and multiple
/// environments use the `default` symlink target if one's set -- or
/// refuse, listing the available names, if not.
pub fn resolve(vault: &Vault, explicit: Option<&str>) -> Result<Option<String>> {
    if let Some(name) = explicit {
        let dir = ensure_dir(vault)?;
        if !dir.join(name).exists() {
            die!("rootfs environment '{name}' doesn't exist -- see 'cas <vault> settings security sandbox rootfs list'");
        }
        return Ok(Some(name.to_string()));
    }

    let dir = vault.rootfs_dir();
    if !dir.exists() {
        return Ok(None);
    }
    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();

    match names.len() {
        0 => Ok(None),
        1 => Ok(Some(names.remove(0))),
        _ => match default_target(vault) {
            Some(name) => Ok(Some(name)),
            None => die!(
                "multiple rootfs environments exist ({}) -- specify one with --rootfs <name>, or set a default: settings security sandbox rootfs default <name>",
                names.join(", ")
            ),
        },
    }
}

/// Removes every rootfs environment -- the same `all` wildcard `rootfs
/// remove all` itself uses (see `RESERVED_NAMES`'s doc comment), reused
/// here so `sandbox disable --removeRootfs` gets identical behavior:
/// typed per-environment confirmation, refuses while any environment
/// is live-in-use, and refuses if a `default` is still set (removal
/// deliberately doesn't auto-clear it -- see `remove.rs`'s own doc
/// comment on why that's not an implicit side effect this takes).
pub fn remove_all(ctx: &Ctx, vault: &Vault) -> Result<()> {
    remove::dispatch(ctx, vault, &["all".to_string()])
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], _pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("list") | None => list(ctx, vault),
        Some("add") => add::dispatch(ctx, vault, &extra[1..]),
        Some("update") => update::dispatch(ctx, vault, &extra[1..]),
        Some("remove") => remove::dispatch(ctx, vault, &extra[1..]),
        Some("rename") => rename::dispatch(ctx, vault, &extra[1..]),
        Some("default") => default::dispatch(ctx, vault, &extra[1..]),
        _ => die!("usage: cas <vault> settings security sandbox rootfs list|add|update|remove|rename|default ..."),
    }
}

fn list(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let dir = ensure_dir(vault)?;
    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();

    if names.is_empty() {
        logf!(ctx, "[i] no rootfs environments yet -- see 'cas help exec'");
        return Ok(());
    }
    let default = default_target(vault);
    for name in names {
        if default.as_deref() == Some(name.as_str()) {
            logf!(ctx, "  {name} (default)");
        } else {
            logf!(ctx, "  {name}");
        }
    }
    Ok(())
}
