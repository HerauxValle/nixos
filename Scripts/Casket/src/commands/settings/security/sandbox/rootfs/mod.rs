// &desc: "`cas <vault> settings security sandbox rootfs list|add|update|remove|rename|default` -- named rootfs environments for `exec --rootfs <name>`. `.rootfs.d/` is created lazily as a real btrfs subvolume the first time any rootfs subcommand runs, not by a migration -- most vaults never use this feature, so nothing about it should touch a vault that doesn't opt in."
use std::fs;

mod add;

use crate::btrfs;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::udisks;
use crate::vault::Vault;

/// Ensures `.rootfs.d/` exists as a real subvolume (creating it, chowned
/// to the real user, on first call) and returns its path. Idempotent --
/// a no-op once it's already there. `.rootfs.d/` deliberately isn't
/// subject to ransomwareProtection's lock (see `Vault::rootfs_dir`'s doc
/// comment), so it's chowned to the real user unconditionally, not
/// gated on that setting the way `.casket/` is.
pub fn ensure_dir(vault: &Vault) -> Result<std::path::PathBuf> {
    let dir = vault.rootfs_dir();
    if !dir.exists() {
        btrfs::subvolume_create(&dir)?;
        udisks::chown_to_real_user(&dir)?;
    }
    Ok(dir)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], _pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("list") | None => list(ctx, vault),
        Some("add") => add::dispatch(ctx, vault, &extra[1..]),
        _ => die!("usage: cas <vault> settings security sandbox rootfs list|add ..."),
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
    for name in names {
        logf!(ctx, "  {name}");
    }
    Ok(())
}
