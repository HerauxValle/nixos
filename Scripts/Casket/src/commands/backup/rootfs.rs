// &desc: "`cas <vault> backup rootfs include|exclude|state` -- which named rootfs environments get an extra snapshot alongside the vault's own, on both manual 'backup create' and the auto-backup rotation. Default is none: since .rootfs.d/ is a real btrfs subvolume, a snapshot of the vault's mount already skips it entirely for free, so an environment only gets swept into backups if explicitly opted in here. .casket/ has no equivalent flag at all -- it's never includable."
use std::fs;

use crate::commands::settings::security::sandbox::rootfs as rootfs_settings;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::vault::Vault;

fn existing_names(vault: &Vault) -> Result<Vec<String>> {
    let dir = rootfs_settings::ensure_dir(vault)?;
    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();
    Ok(names)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String]) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("include") => set(ctx, vault, extra.get(1), true),
        Some("exclude") => set(ctx, vault, extra.get(1), false),
        Some("state") | None => state(ctx, vault),
        _ => die!("usage: cas <vault> backup rootfs include|exclude <name>|all | state"),
    }
}

fn set(ctx: &Ctx, vault: &Vault, target: Option<&String>, include: bool) -> Result<()> {
    let Some(target) = target else {
        die!("usage: cas <vault> backup rootfs {}<name>|all", if include { "include " } else { "exclude " });
    };

    let mut meta = Meta::read(&vault.img);
    let mut current = meta.sandbox_backup_rootfs.clone().unwrap_or_default();

    let targets: Vec<String> = if target == "all" {
        if include { existing_names(vault)? } else { current.clone() }
    } else {
        if include && !existing_names(vault)?.contains(target) {
            die!("rootfs environment '{target}' doesn't exist -- see 'cas <vault> settings security sandbox rootfs list'");
        }
        vec![target.clone()]
    };

    if include {
        for name in &targets {
            if !current.contains(name) {
                current.push(name.clone());
            }
        }
    } else {
        current.retain(|n| !targets.contains(n));
    }
    current.sort();

    meta.sandbox_backup_rootfs = if current.is_empty() { None } else { Some(current) };
    meta.write(&vault.img)?;

    let verb = if include { "included in" } else { "excluded from" };
    logf!(ctx, "[✓] {} now {verb} backups", targets.join(", "));
    Ok(())
}

fn state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    match meta.sandbox_backup_rootfs {
        Some(names) if !names.is_empty() => {
            for name in names {
                logf!(ctx, "  {name}");
            }
        }
        _ => logf!(ctx, "[i] no rootfs environments are included in backups"),
    }
    Ok(())
}
