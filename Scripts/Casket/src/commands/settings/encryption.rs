// &desc: "`cas <vault> settings encryption enable|disable` — toggle the passphrase-prompt UX by storing (or clearing) the LUKS secret in metadata as a base64 autokey. Already self-verifies via the real passphrase below, so `gate()` is a no-op unless verification is explicitly turned on for this feature too."
use crate::commands::settings::gate::gate_pw;
use crate::commands::settings::registry::Feature;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::secret::{b64_encode, combined_secret, resolve_keyfile};
use crate::vault::Vault;

pub const FEATURE: Feature = Feature {
    name: "encryption",
    set,
    get: |meta| !meta.is_encryption_bypassed(),
};

fn set(ctx: &Ctx, vault: &Vault, enable: bool, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let pw = gate_pw(ctx, vault, "encryption", pw)?;
    let mut meta = Meta::read(&vault.img);
    // Always derive the secret from pw (+ keyfile if 2FA) — never the
    // autokey shortcut — so this genuinely re-verifies the real
    // passphrase rather than trusting whatever's already stored.
    let secret = match meta.keyfile.clone() {
        Some(cached) => {
            let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img, crate::version::CURRENT)?;
            combined_secret(&pw, &crate::keyfile::read_bytes(&kf_path)?)
        }
        None => pw.as_bytes().to_vec(),
    };

    Meta::strip(&vault.img)?;
    if !luks::test(&vault.img, &secret) {
        meta.write(&vault.img)?;
        die!("wrong passphrase — could not verify vault");
    }

    if !enable {
        meta.encrypted = Some(false);
        meta.autokey = Some(b64_encode(&secret));
        meta.write(&vault.img)?;
        logf!(ctx, "[✓] encryption UX disabled — vault will open without prompting for a passphrase");
        logf!(ctx, "    Note: data is still LUKS-encrypted on disk. This only skips the prompt.");
    } else {
        meta.autokey = None;
        meta.encrypted = None;
        meta.write(&vault.img)?;
        logf!(ctx, "[✓] encryption UX enabled — passphrase required to open vault");
    }
    Ok(())
}
