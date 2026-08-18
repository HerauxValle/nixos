// &desc: "`cas <vault> info` — full vault picture in one place: [general] path/size/open/slots, [auth] passphrase + keyfile identity, [settings] encryption/2fa/backupAuto, [security] features, [verification] per-feature gating. Settings/security/verification sections walk the same Feature registries `settings ... state` uses, so a new setting shows up here automatically."
use crate::commands::settings::{backup_auto, gate, registry, security, FLAT_FEATURES};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::keyfile;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::secret::{combined_secret, resolve_keyfile};
use crate::tamper;
use crate::vault::Vault;
use std::path::Path;

pub fn run(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    let (mut meta, schema_from) = Meta::read_versioned(&vault.img);

    // `info` stays auth-free by default (that's the point of it), but if
    // a passphrase is given, opportunistically verify it and check the
    // tamper HMAC too — extra assurance without making it mandatory.
    // A wrong passphrase here is silently skipped rather than dying;
    // this is still a read-only command. `pw_verified` also gates the
    // keyfile's exact path below (see [auth]) — a 2FA vault whose `info`
    // hands over the second factor's exact location to anyone with mere
    // read access to the vault directory, no passphrase required, isn't
    // really 2FA anymore. It's found for free once you have factor one.
    let mut pw_verified = false;
    if let Some(pw) = pw {
        let secret = match meta.keyfile.clone() {
            Some(cached) => {
                let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img, schema_from)?;
                combined_secret(pw, &crate::keyfile::read_bytes(&kf_path)?)
            }
            None => pw.as_bytes().to_vec(),
        };
        Meta::strip(&vault.img)?;
        let ok = luks::test(&vault.img, &secret);
        // `write_at_version`, not `write` -- `info` never runs
        // `migrations::migrate_layout` (that needs a mount, `open`'s
        // job), so persisting this restore at `schema_from` instead of
        // jumping to `version::CURRENT` keeps a future `open` able to
        // see any layout migration this vault still actually owes. See
        // `Meta::write_at_version`'s doc comment for the incident this
        // fixes.
        meta.write_at_version(&vault.img, schema_from)?;
        pw_verified = ok;
        if ok {
            match tamper::verify(&secret, &meta) {
                tamper::Status::Healthy => logf!(ctx, "[✓] tamper check: healthy"),
                tamper::Status::Tampered => logf!(ctx, "[x] tamper check: TAMPERED — see 'cas {} tampered' for details", vault.name),
                tamper::Status::Unprotected => logf!(ctx, "[i] tamper check: no baseline yet"),
            }
        } else {
            logf!(ctx, "  [!] --pass didn't verify — skipping tamper check");
        }
    }
    let size_mb = vault.img.metadata()?.len() / (1024 * 1024);
    let mounted = if vault.is_mount() {
        format!("yes  ->  {}", vault.mnt.display())
    } else {
        "no".to_string()
    };
    let slots = luks::slot_count(&vault.img);

    // One column width for the entire `info` dump — every name in
    // every section, [general] through [verification], is measured
    // together so the value column lines up top to bottom, not just
    // within whichever section happens to share a `line()`/`kv_line()`
    // call together.
    let mut names: Vec<&str> = vec!["vault", "size", "open", "slots", "passphrase", "keyfile", "keep", "threshold"];
    names.extend(FLAT_FEATURES.iter().map(|f| f.name));
    names.push("backupAuto");
    names.extend(security::FEATURES.iter().map(|f| f.name));
    names.extend(gate::GATED_FEATURES.iter().copied());
    let width = registry::column_width(&names);

    logf!(ctx, "{}", registry::section("general"));
    logf!(ctx, "{}", registry::kv_line("vault", &vault.img.display().to_string(), width));
    logf!(ctx, "{}", registry::kv_line("size", &format!("{size_mb} MiB"), width));
    logf!(ctx, "{}", registry::kv_line("open", &mounted, width));
    logf!(ctx, "{}", registry::kv_line("slots", &format!("{slots} active"), width));

    logf!(ctx, "{}", registry::section("auth"));
    let passphrase = if meta.is_encryption_bypassed() { "bypassed  (open won't prompt — see settings encryption)" } else { "required" };
    logf!(ctx, "{}", registry::kv_line("passphrase", passphrase, width));
    match &meta.keyfile {
        Some(kf) => {
            let kind = if keyfile::is_embedded(Path::new(kf)) { "embedded" } else { "raw file" };
            if pw_verified {
                logf!(ctx, "{}", registry::kv_line("keyfile", &format!("{kf}  ({kind})"), width));
            } else {
                logf!(ctx, "{}", registry::kv_line("keyfile", &format!("set  ({kind}, path hidden — pass --pass to reveal)"), width));
            }
        }
        None => logf!(ctx, "{}", registry::kv_line("keyfile", "none", width)),
    }

    logf!(ctx, "{}", registry::section("settings"));
    for f in FLAT_FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta), width));
    }
    logf!(ctx, "{}", registry::line("backupAuto", backup_auto::is_enabled(&meta), width));
    if backup_auto::is_enabled(&meta) {
        // Extra "  " here nests `keep` visually under backupAuto, so the
        // name field is 2 narrower than everyone else's to keep the
        // value column lined up with the rest of the output.
        logf!(ctx, "  {}", registry::kv_line("keep", &meta.backup_auto_keep_or(3).to_string(), width.saturating_sub(2)));
    }

    logf!(ctx, "{}", registry::section("security"));
    for f in security::FEATURES {
        logf!(ctx, "{}", registry::line(f.name, (f.get)(&meta), width));
        if f.name == "bruteforceLockout" && (f.get)(&meta) {
            logf!(ctx, "  {}", registry::kv_line("threshold", &security::bruteforce_lockout::threshold(&meta).to_string(), width.saturating_sub(2)));
        }
    }

    logf!(ctx, "{}", registry::section("verification"));
    logf!(ctx, "{}", registry::VERIFICATION_NOTE);
    for feature in gate::GATED_FEATURES {
        logf!(ctx, "{}", registry::line(feature, gate::requires_verification(&meta, feature), width));
    }
    logf!(ctx, "");
    Ok(())
}
