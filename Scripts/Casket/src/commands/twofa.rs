// &desc: "`cas <vault> 2fa on|off` — generate/remove the 2FA keyfile and re-key the vault to/from a passphrase+keyfile combined secret."
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;

use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::secret::{b64_encode, combined_secret, get_secret, resolve_keyfile};
use crate::udisks;
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, sub: &str, pw: &str) -> Result<()> {
    match sub {
        "on" => on(ctx, vault, pw),
        "off" => off(ctx, vault, pw),
        _ => die!("usage: cas <vault> 2fa on|off\n    Run 'cas help 2fa' for details."),
    }
}

fn on(ctx: &Ctx, vault: &Vault, pw: &str) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let meta = Meta::read(&vault.img);
    if meta.keyfile.is_some() {
        die!("2FA is already enabled\n    Run 'cas {} 2fa off' first.", vault.name);
    }

    // Respects the encryption=off autokey shortcut the same way `open`
    // does — no prompt needed if the vault is already unlocked-by-default.
    let (old_secret, _) = get_secret(ctx, &vault.img, pw, None, Some(meta.clone()))?;

    let kf_path = vault.base().join(format!("{}.key", vault.name));
    let mut key_bytes = [0u8; 64];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut key_bytes);
    {
        // Created with 0600 from the first syscall — no separate chmod,
        // so there's no window where the key sits at default umask perms.
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&kf_path)?;
        f.write_all(&key_bytes)?;
    }
    udisks::chown_to_real_user(&kf_path)?;
    logf!(ctx, "  [i] generated keyfile: {}", kf_path.display());
    logf!(ctx, "      Back this up — losing it means losing access to the vault.");

    let new_secret = combined_secret(pw, &key_bytes);
    logf!(ctx, "[cas] enabling 2FA on '{}' ...", vault.name);
    Meta::strip(&vault.img)?;

    let mut new_meta = Meta { keyfile: Some(kf_path.to_string_lossy().into_owned()), ..Meta::default() };
    if meta.encrypted == Some(false) {
        new_meta.encrypted = Some(false);
        new_meta.autokey = Some(b64_encode(&new_secret));
    }

    if let Err(e) = luks::slot_cycle(ctx, &vault.img, &old_secret, &new_secret, None) {
        meta.write(&vault.img)?;
        let _ = std::fs::remove_file(&kf_path);
        return Err(e);
    }

    new_meta.write(&vault.img)?;
    logf!(ctx, "[✓] 2FA enabled — keyfile: {}", kf_path.display());
    logf!(ctx, "    You now need BOTH your passphrase AND that keyfile to open this vault.");
    Ok(())
}

fn off(ctx: &Ctx, vault: &Vault, pw: &str) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let mut meta = Meta::read(&vault.img);
    if meta.keyfile.is_none() {
        die!("2FA is not enabled on this vault");
    }
    let cached = meta.keyfile.clone().unwrap();
    let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img)?;
    let kf_bytes = std::fs::read(&kf_path)?;
    let old_secret = combined_secret(pw, &kf_bytes);
    let new_secret = pw.as_bytes().to_vec();

    logf!(ctx, "[cas] disabling 2FA on '{}' ...", vault.name);
    Meta::strip(&vault.img)?;

    let mut new_meta = Meta::default();
    if meta.encrypted == Some(false) {
        new_meta.encrypted = Some(false);
        new_meta.autokey = Some(b64_encode(&new_secret));
    }

    if let Err(e) = luks::slot_cycle(ctx, &vault.img, &old_secret, &new_secret, None) {
        meta.write(&vault.img)?;
        return Err(e);
    }

    std::fs::remove_file(&kf_path)?;
    new_meta.write(&vault.img)?;
    logf!(ctx, "[✓] 2FA disabled — passphrase alone is sufficient again");
    logf!(ctx, "  [i] keyfile deleted: {}", kf_path.display());
    Ok(())
}
