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

    let general_width = registry::column_width(&["vault", "size", "open", "slots"]);
    logf!(ctx, "{}", registry::section("general"));
    logf!(ctx, "{}", registry::kv_line("vault", &vault.img.display().to_string(), general_width));
    logf!(ctx, "{}", registry::kv_line("size", &format!("{size_mb} MiB"), general_width));
    logf!(ctx, "{}", registry::kv_line("open", &mounted, general_width));
    logf!(ctx, "{}", registry::kv_line("slots", &format!("{slots} active"), general_width));

    let auth_width = registry::column_width(&["passphrase", "keyfile"]);
    logf!(ctx, "{}", registry::section("auth"));
    let passphrase = if meta.is_encryption_bypassed() { "bypassed  (open won't prompt — see settings encryption)" } else { "required" };
    logf!(ctx, "{}", registry::kv_line("passphrase", passphrase, auth_width));
    match &meta.keyfile {
        Some(kf) => {
            let kind = if keyfile::is_embedded(Path::new(kf)) { "embedded" } else { "raw file" };
            logf!(ctx, "{}", registry::kv_line("keyfile", &format!("{kf}  ({kind})"), auth_width));
        }
        None => logf!(ctx, "{}", registry::kv_line("keyfile", "none", auth_width)),
    }

    // One shared column width across settings/security/verification so
    // the value column lines up across every section, not just within
    // each one — otherwise a long name in one section (e.g.
    // ransomwareProtection) sits at a different column than a short
    // name in another (e.g. 2fa).
    let mut names: Vec<&str> = FLAT_FEATURES.iter().map(|f| f.name).collect();
    names.push("backupAuto");
    names.extend(security::FEATURES.iter().map(|f| f.name));
    names.extend(gate::GATED_FEATURES.iter().copied());
    let width = registry::column_width(&names);

    logf!(ctx, "{}", registry::section("settings"));
    for f in FLAT_FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta), width));
    }
    logf!(ctx, "{}", registry::line("backupAuto", backup_auto::is_enabled(&meta), width));
    if backup_auto::is_enabled(&meta) {
        logf!(ctx, "    keep      {}", meta.backup_auto_keep_or(3));
    }

    logf!(ctx, "{}", registry::section("security"));
    for f in security::FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta), width));
    }

    logf!(ctx, "{}", registry::section("verification"));
    logf!(ctx, "{}", registry::VERIFICATION_NOTE);
    for feature in gate::GATED_FEATURES {
        logf!(ctx, "{}", registry::line(feature, gate::requires_verification(&meta, feature), width));
    }
    logf!(ctx, "");
    Ok(())
}
