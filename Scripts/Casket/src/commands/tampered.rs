// &desc: "`cas <vault> tampered [--pass ...]` — on-demand tamper check: resolves and cryptographically verifies the real passphrase, then reports whether the tamper-protected fields (see tamper.rs's Protected struct) match the last passphrase-verified write. Always resolves a real passphrase (like auth passwd), since a check that could pass without one would also let an attacker forge a matching result without one."
use crate::commands::settings::gate::gate_pw;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::secret::{combined_secret, resolve_keyfile};
use crate::tamper;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }

    let pw = gate_pw(ctx, vault, "tampered", pw)?;
    let (mut meta, schema_from) = Meta::read_versioned(&vault.img);
    let secret = match meta.keyfile.clone() {
        Some(cached) => {
            let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img, schema_from)?;
            combined_secret(&pw, &crate::keyfile::read_bytes(&kf_path)?)
        }
        None => pw.as_bytes().to_vec(),
    };
    Meta::strip(&vault.img)?;
    let ok = luks::test(&vault.img, &secret);
    // `write_at_version`, not `write` -- same fix as `info.rs`, see
    // `Meta::write_at_version`'s doc comment. `tampered` never runs
    // `migrations::migrate_layout` either.
    meta.write_at_version(&vault.img, schema_from)?;
    if !ok {
        die!("wrong passphrase — could not verify vault");
    }

    match tamper::verify(&secret, &meta) {
        tamper::Status::Healthy => logf!(ctx, "[✓] '{}' healthy — metadata matches the last verified write", vault.name),
        tamper::Status::Tampered => {
            logf!(ctx, "[x] '{}' tampered — one or more protected settings don't match the last verified write", vault.name);
            logf!(ctx, "    run 'cas {} open' to reset those settings to their safe defaults, or review them yourself first", vault.name);
        }
        tamper::Status::Unprotected => logf!(ctx, "[i] '{}' has no tamper baseline yet — no verified write has happened since this feature existed", vault.name),
    }
    Ok(())
}
