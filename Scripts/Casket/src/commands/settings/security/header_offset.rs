// &desc: "`cas <vault> settings security headerOffset enable | disable | state` — relocates the vault's LUKS2 header from the container's front to a passphrase-derived slot inside a header-hiding room (see header/relocate.rs), so a magic-byte scan of the front no longer finds it. Direct-dispatch (not registry::Feature) since enable prints a conditional headerEncryption notice, following bruteforce_lockout.rs's pattern."
use crate::commands::settings::gate::gate_pw;
use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::header::relocate;
use crate::logf;
use crate::meta::Meta;
use crate::secret::{combined_secret, resolve_keyfile};
use crate::vault::Vault;

pub fn is_enabled(meta: &Meta) -> bool {
    relocate::offset_enabled(meta)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => run(ctx, vault, true, pw),
        Some("disable") => run(ctx, vault, false, pw),
        Some("state") => {
            relocate::resume_scrub_if_pending(&vault.img);
            let meta = Meta::read(&vault.img);
            logf!(ctx, "{}", crate::commands::settings::registry::line("headerOffset", is_enabled(&meta), crate::commands::settings::registry::column_width(&["headerOffset"])));
            Ok(())
        }
        _ => die!("usage: cas <vault> settings security headerOffset enable | disable | state"),
    }
}

fn resolve_secret(ctx: &Ctx, vault: &Vault, meta: &Meta, pw: &str) -> Result<Vec<u8>> {
    match meta.keyfile.clone() {
        Some(cached) => {
            let mut m = meta.clone();
            let kf_path = resolve_keyfile(ctx, &cached, &mut m, &vault.img, crate::version::CURRENT)?;
            Ok(combined_secret(pw, &crate::keyfile::read_bytes(&kf_path)?))
        }
        None => Ok(pw.as_bytes().to_vec()),
    }
}

fn run(ctx: &Ctx, vault: &Vault, enable: bool, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault must be closed first:  cas {} close", vault.name);
    }

    relocate::resume_scrub_if_pending(&vault.img);

    let meta_before = Meta::read(&vault.img);
    if is_enabled(&meta_before) == enable {
        let word = if enable { "enabled" } else { "disabled" };
        die!("headerOffset is already {word} for '{}'", vault.name);
    }

    let pw = gate_pw(ctx, vault, "headerOffset", pw)?;
    let secret = resolve_secret(ctx, vault, &meta_before, &pw)?;
    if !relocate::verify_current_secret(vault, &meta_before, &secret) {
        die!("wrong passphrase — could not verify vault");
    }

    let mut meta = meta_before;
    logf!(ctx, "[cas] {} headerOffset for '{}' ...", if enable { "enabling" } else { "disabling" }, vault.name);

    if enable {
        relocate::enable_offset(ctx, vault, &mut meta, &secret, Strength::default())?;
        logf!(ctx, "[✓] headerOffset enabled for '{}'", vault.name);
        if !relocate::encryption_enabled(&meta) {
            logf!(ctx, "  [i] the relocated header's content is not encrypted (headerEncryption is off) — position alone is now hidden, content is still a plain, parseable LUKS2 header to anyone who finds the slot");
            logf!(ctx, "      cas {} settings security headerEncryption enable", vault.name);
        }
    } else {
        relocate::disable_offset(ctx, vault, &mut meta, &secret, Strength::default())?;
        logf!(ctx, "[✓] headerOffset disabled for '{}'", vault.name);
    }
    Ok(())
}
