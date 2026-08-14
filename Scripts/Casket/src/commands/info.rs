// &desc: "`cas <vault> info` — print path, size, open state, active LUKS slot count, and every registered setting's enabled|disabled state (encryption, 2fa, security, backupAuto, verification) rolled up in one place. Walks the same Feature registries `settings ... state` uses, so a new setting shows up here automatically — nothing to hand-wire."
use crate::commands::settings::{backup_auto, gate, registry, security, FLAT_FEATURES};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    let meta = Meta::read(&vault.img);
    let size_mb = vault.img.metadata()?.len() / (1024 * 1024);
    let mounted = if vault.is_mount() {
        format!("yes  ->  {}", vault.mnt.display())
    } else {
        "no".to_string()
    };
    let slots = luks::slot_count(&vault.img);

    logf!(ctx, "\n  vault     {}\n  size      {size_mb} MiB\n  open      {mounted}\n  slots     {slots} active\n", vault.img.display());

    for f in FLAT_FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta)));
        if f.name == "2fa" {
            if let Some(kf) = &meta.keyfile {
                logf!(ctx, "    keyfile   {kf}");
            }
        }
    }

    for f in security::FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta)));
    }

    logf!(ctx, "{}", registry::line("backupAuto", backup_auto::is_enabled(&meta)));
    if backup_auto::is_enabled(&meta) {
        logf!(ctx, "    keep      {}", meta.backup_auto_keep_or(3));
    }

    for feature in gate::GATED_FEATURES {
        logf!(ctx, "{}", registry::line(&format!("verification-{feature}"), gate::requires_verification(&meta, feature)));
    }
    logf!(ctx, "");
    Ok(())
}
