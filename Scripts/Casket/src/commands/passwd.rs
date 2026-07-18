// &desc: "`cas <vault> passwd` — change the passphrase via the safe slot_cycle rotation, re-deriving the 2FA combined secret if a keyfile is set."
use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::{b64_encode, combined_secret, resolve_keyfile};
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

    let new_pw = match new_pw {
        Some(p) if !p.is_empty() => p.to_string(),
        _ => {
            let np = prompt::ask_secret(ctx, "new passphrase")?;
            let confirm = prompt::ask_secret(ctx, "confirm new passphrase")?;
            if np != confirm {
                die!("passphrases don't match");
            }
            np
        }
    };
    if new_pw.is_empty() {
        die!("passphrase cannot be empty");
    }

    let mut meta = Meta::read(&vault.img);
    let (old_secret, new_secret) = if let Some(cached) = meta.keyfile.clone() {
        let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img)?;
        let kf_bytes = std::fs::read(&kf_path)?;
        (combined_secret(&old_pw, &kf_bytes), combined_secret(&new_pw, &kf_bytes))
    } else {
        (old_pw.into_bytes(), new_pw.into_bytes())
    };

    let strength_label = strength.map(|s| s.to_string()).unwrap_or_else(|| "unchanged".to_string());
    logf!(ctx, "[cas] changing passphrase for '{}' (strength={strength_label}) ...", vault.name);
    Meta::strip(&vault.img)?;

    if let Err(e) = luks::slot_cycle(ctx, &vault.img, &old_secret, &new_secret, strength) {
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
