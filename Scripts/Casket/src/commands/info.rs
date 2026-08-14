// &desc: "`cas <vault> info` — full vault picture in one place: [general] path/size/open/slots, [auth] passphrase + keyfile identity, [settings] encryption/2fa/backupAuto, [security] features, [verification] per-feature gating. Settings/security/verification sections walk the same Feature registries `settings ... state` uses, so a new setting shows up here automatically."
use crate::commands::settings::{backup_auto, gate, registry, security, FLAT_FEATURES};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::keyfile;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::vault::Vault;
use std::path::Path;

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

    logf!(ctx, "{}", registry::section("general"));
    logf!(ctx, "  vault     {}\n  size      {size_mb} MiB\n  open      {mounted}\n  slots     {slots} active", vault.img.display());

    logf!(ctx, "{}", registry::section("auth"));
    let passphrase = if meta.is_encryption_bypassed() { "bypassed  (open won't prompt — see settings encryption)" } else { "required" };
    logf!(ctx, "  passphrase  {passphrase}");
    match &meta.keyfile {
        Some(kf) => {
            let kind = if keyfile::is_embedded(Path::new(kf)) { "embedded" } else { "raw file" };
            logf!(ctx, "  keyfile     {kf}  ({kind})");
        }
        None => logf!(ctx, "  keyfile     none"),
    }

    logf!(ctx, "{}", registry::section("settings"));
    for f in FLAT_FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta)));
    }
    logf!(ctx, "{}", registry::line("backupAuto", backup_auto::is_enabled(&meta)));
    if backup_auto::is_enabled(&meta) {
        logf!(ctx, "    keep      {}", meta.backup_auto_keep_or(3));
    }

    logf!(ctx, "{}", registry::section("security"));
    for f in security::FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta)));
    }

    logf!(ctx, "{}", registry::section("verification"));
    for feature in gate::GATED_FEATURES {
        logf!(ctx, "{}", registry::line(feature, gate::requires_verification(&meta, feature)));
    }
    logf!(ctx, "");
    Ok(())
}
