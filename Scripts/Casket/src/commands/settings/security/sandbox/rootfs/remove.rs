// &desc: "`rootfs remove <name>|<name,name,...>|all` -- typed-confirm per environment (against the environment's own name, not the vault's), refuses while any 'cas exec' session is live or if the target is the current default (clear the default first -- removal doesn't auto-update it the way rename does, since removal is destructive and shouldn't carry an implicit side effect)."
use std::fs;

use crate::commands::exec::lockfile;
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::rootfs::{default_target, ensure_dir, validate_name};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::prompt;
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let Some(raw) = extra.first() else {
        die!("usage: cas <vault> settings security sandbox rootfs remove <name>|<name,name,...>|all");
    };

    if vault.is_mount() && lockfile::is_live(vault) {
        die!("'{}' has a live 'cas exec' session -- wait for it to exit before removing a rootfs environment", vault.name);
    }
    gate_inner(ctx, vault, "sandbox", pw)?;

    let dir = ensure_dir(vault)?;
    let names: Vec<String> = if raw == "all" {
        fs::read_dir(&dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
            .filter_map(|e| e.file_name().into_string().ok())
            .collect()
    } else {
        raw.split(',').map(str::trim).filter(|s| !s.is_empty()).map(str::to_string).collect()
    };
    if names.is_empty() {
        logf!(ctx, "[i] nothing to remove");
        return Ok(());
    }

    let default = default_target(vault);
    for name in &names {
        validate_name(name)?;
        if !dir.join(name).exists() {
            die!("rootfs environment '{name}' doesn't exist -- see 'cas <vault> settings security sandbox rootfs list'");
        }
        if default.as_deref() == Some(name.as_str()) {
            die!("'{name}' is the current default -- clear it first: rootfs default --clear");
        }
    }

    for name in &names {
        let warning = format!("this permanently deletes rootfs environment '{name}' and everything installed in it");
        if !prompt::confirm_named(ctx, name, "environment", &warning)? {
            die!("aborted");
        }
        fs::remove_dir_all(dir.join(name))?;
        logf!(ctx, "[✓] removed '{name}'");
    }
    Ok(())
}
