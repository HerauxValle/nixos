// &desc: "`cas <vault> auth passwd` — change the passphrase via the safe slot_cycle rotation, re-deriving the 2FA combined secret if a keyfile is set."
use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::header::relocate;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::{b64_encode, combined_secret, generate_passphrase, resolve_keyfile, weakness_warning};
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, old_pw: &str, new_pw: Option<&str>, strength: Option<Strength>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let old_pw = if old_pw.is_empty() {
        prompt::ask_secret(ctx, "current passphrase")?
    } else {
        old_pw.to_string()
    };

    let typed_pw = match new_pw {
        Some(p) if !p.is_empty() => p.to_string(),
        Some(_) => String::new(), // --new-pass "" explicitly given: generate, same as create
        None => {
            let np = prompt::ask_secret(ctx, "new passphrase (leave empty to generate a strong one)")?;
            if np.is_empty() {
                String::new()
            } else {
                let confirm = prompt::ask_secret(ctx, "confirm new passphrase")?;
                if np != confirm {
                    die!("passphrases don't match");
                }
                np
            }
        }
    };

    // Leaving it empty generates a strong one, same as `create` — this
    // used to just refuse an empty new passphrase, an inconsistency
    // with `create`'s own behavior for no real reason: rotating *to* a
    // strong passphrase should be exactly as easy as creating one was.
    let generated;
    let new_pw: &str = if typed_pw.is_empty() {
        generated = generate_passphrase();
        logf!(ctx, "  [i] generated passphrase: {generated}");
        logf!(ctx, "      Save this — it cannot be recovered!");
        &generated
    } else {
        if let Some(warning) = weakness_warning(&typed_pw) {
            logf!(ctx, "  [!] weak passphrase: {warning}");
        }
        &typed_pw
    };

    let mut meta = Meta::read(&vault.img);
    let (old_secret, new_secret) = if let Some(cached) = meta.keyfile.clone() {
        let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img, crate::version::CURRENT)?;
        let kf_bytes = crate::keyfile::read_bytes(&kf_path)?;
        (combined_secret(&old_pw, &kf_bytes), combined_secret(new_pw, &kf_bytes))
    } else {
        (old_pw.into_bytes(), new_pw.as_bytes().to_vec())
    };

    let strength_label = strength.map(|s| s.to_string()).unwrap_or_else(|| "unchanged".to_string());
    logf!(ctx, "[cas] changing passphrase for '{}' (strength={strength_label}) ...", vault.name);
    Meta::strip(&vault.img)?;

    // Not just offset_enabled -- headerEncryption alone also leaves the
    // container's front bytes undtestable by a plain (non-`--header`)
    // cryptsetup call (they're AEAD ciphertext, not a parseable LUKS2
    // header), same failure mode as headerOffset. is_native_front
    // (false) covers all three "something's relocated and/or encrypted"
    // states with one check, matching the same fix already applied to
    // settings::twofa's identical branch after this exact bug class was
    // confirmed live there.
    let cycle_result: Result<()> = if !relocate::is_native_front(&meta) {
        (|| -> Result<()> {
            let salt = crate::header::room::read_salt(&vault.img)
                .ok_or_else(|| CasError::new("header room not found — vault metadata is inconsistent"))?;
            let master = crate::header::derive_master_secret(&[old_secret.as_slice()], &salt);
            let staged = relocate::stage_current_header(vault, &meta, Some(&master))?;
            luks::slot_cycle_detached(ctx, staged.path(), &vault.img, &old_secret, &new_secret, strength)
        })()
    } else {
        luks::slot_cycle(ctx, &vault.img, &old_secret, &new_secret, strength)
    };
    if let Err(e) = cycle_result {
        meta.write(&vault.img)?;
        return Err(e);
    }

    // Both toggles' actual relocation/re-encryption happens here,
    // strictly between slot_cycle succeeding and meta.write() —
    // relocate_if_enabled itself does the verify-before-commit-before-
    // scrub dance under the *new* secret, same discipline as enable.
    if let Err(e) = relocate::relocate_if_enabled(ctx, vault, &mut meta, &old_secret, &new_secret, strength) {
        meta.write(&vault.img)?;
        return Err(e);
    }

    if meta.is_encryption_bypassed() {
        meta.autokey = Some(b64_encode(&new_secret));
        logf!(ctx, "  [i] updated stored autokey (encryption off mode)");
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] passphrase updated");
    Ok(())
}
