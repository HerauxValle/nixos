// &desc: "`cas <vault> settings security headerEncryption enable|disable|state` — ChaCha20-Poly1305-encrypts the LUKS2 header's content wherever it currently lives (front or a headerOffset room slot), on top of whatever position hiding headerOffset already provides. Direct-dispatch, same shape as header_offset.rs."
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
    relocate::encryption_enabled(meta)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => run(ctx, vault, true, pw),
        Some("disable") => run(ctx, vault, false, pw),
        Some("state") => {
            let meta = Meta::read(&vault.img);
            logf!(ctx, "{}", crate::commands::settings::registry::line("headerEncryption", is_enabled(&meta), crate::commands::settings::registry::column_width(&["headerEncryption"])));
            Ok(())
        }
        _ => die!("usage: cas <vault> settings security headerEncryption enable|disable|state"),
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

    let meta_before = Meta::read(&vault.img);
    if is_enabled(&meta_before) == enable {
        let word = if enable { "enabled" } else { "disabled" };
        die!("headerEncryption is already {word} for '{}'", vault.name);
    }
    let pw = gate_pw(ctx, vault, "headerEncryption", pw)?;
    let secret = resolve_secret(ctx, vault, &meta_before, &pw)?;
    if !relocate::verify_current_secret(vault, &meta_before, &secret) {
        die!("wrong passphrase — could not verify vault");
    }

    let mut meta = meta_before;
    logf!(ctx, "[cas] {} headerEncryption for '{}' ...", if enable { "enabling" } else { "disabling" }, vault.name);

    if enable {
        relocate::enable_encryption(ctx, vault, &mut meta, &secret, Strength::default())?;
        logf!(ctx, "[✓] headerEncryption enabled for '{}'", vault.name);
        if !relocate::offset_enabled(&meta) {
            logf!(ctx, "  [i] the header is still at its normal front position (headerOffset is off) — content is hidden, but the header's *location* is not:");
            logf!(ctx, "      cas {} settings security headerOffset enable", vault.name);
        }
    } else {
        relocate::disable_encryption(ctx, vault, &mut meta, &secret, Strength::default())?;
        logf!(ctx, "[✓] headerEncryption disabled for '{}'", vault.name);
    }
    Ok(())
}
