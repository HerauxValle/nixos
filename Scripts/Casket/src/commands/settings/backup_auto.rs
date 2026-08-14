// &desc: "`cas <vault> settings backup auto enable|disable|keep` — persist the per-vault auto-snapshot-on-open policy into metadata. Not a plain enable/disable Feature (`keep <N>` is a third verb with its own argument), so it's dispatched directly by settings/mod.rs rather than through registry::dispatch."
use crate::commands::settings::gate::gate;
use crate::commands::settings::registry;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::vault::Vault;

pub fn is_enabled(meta: &Meta) -> bool {
    meta.backup_auto == Some(true)
}

fn is_positive_int(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => {
            let mut keep = 3u32;
            if extra.get(1).map(String::as_str) == Some("--keep") {
                let valid = extra.get(2).is_some_and(|s| is_positive_int(s));
                if !valid {
                    die!("usage: cas <vault> settings backup auto enable [--keep N]");
                }
                keep = extra[2].parse().unwrap();
                if keep < 1 {
                    die!("--keep must be at least 1");
                }
            }
            gate(ctx, vault, "backupAuto", pw)?;
            enable(ctx, vault, keep)
        }
        Some("disable") => {
            gate(ctx, vault, "backupAuto", pw)?;
            disable(ctx, vault)
        }
        Some("state") => {
            let meta = Meta::read(&vault.img);
            let width = registry::column_width(&["backupAuto", "keep"]);
            logf!(ctx, "{}", registry::line("backupAuto", is_enabled(&meta), width));
            if is_enabled(&meta) {
                logf!(ctx, "  {}", registry::kv_line("keep", &meta.backup_auto_keep_or(3).to_string(), width));
            }
            Ok(())
        }
        Some("keep") => {
            let valid = extra.get(1).is_some_and(|s| is_positive_int(s));
            if !valid {
                die!("usage: cas <vault> settings backup auto keep <N>\n    Example:  cas myvault settings backup auto keep 5");
            }
            let keep: u32 = extra[1].parse().unwrap();
            if keep < 1 {
                die!("keep must be at least 1");
            }
            set_keep(ctx, vault, keep)
        }
        _ => die!("usage: cas <vault> settings backup auto enable [--keep N] | disable | keep <N> | state"),
    }
}

fn require_closed(vault: &Vault) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }
    Ok(())
}

fn enable(ctx: &Ctx, vault: &Vault, keep: u32) -> Result<()> {
    require_closed(vault)?;
    let mut meta = Meta::read(&vault.img);
    meta.backup_auto = Some(true);
    meta.backup_auto_keep = Some(keep);
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] auto-backup enabled for '{}' (keep={keep})", vault.name);
    logf!(ctx, "    a timestamped snapshot will be created each time the vault is opened");
    Ok(())
}

fn disable(ctx: &Ctx, vault: &Vault) -> Result<()> {
    require_closed(vault)?;
    let mut meta = Meta::read(&vault.img);
    meta.backup_auto = None;
    meta.backup_auto_keep = None;
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] auto-backup disabled for '{}'", vault.name);
    logf!(ctx, "    existing auto-backups are kept — delete them manually if needed");
    Ok(())
}

fn set_keep(ctx: &Ctx, vault: &Vault, keep: u32) -> Result<()> {
    require_closed(vault)?;
    let mut meta = Meta::read(&vault.img);
    if meta.backup_auto != Some(true) {
        die!("auto-backup is not enabled — run 'cas {} settings backup auto enable' first", vault.name);
    }
    meta.backup_auto_keep = Some(keep);
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] auto-backup keep limit set to {keep} for '{}'", vault.name);
    logf!(ctx, "    excess snapshots will be pruned on the next open");
    Ok(())
}
