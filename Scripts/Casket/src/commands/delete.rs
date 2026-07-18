// &desc: "`cas <vault> delete` — permanently remove the vault file and its keyfile, after a typed-name confirmation."
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::resolve_keyfile;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let mut meta = Meta::read(&vault.img);
    let kf_path = match meta.keyfile.clone() {
        Some(cached) => Some(resolve_keyfile(ctx, &cached, &mut meta, &vault.img)?),
        None => None,
    };

    let warning = format!("This will permanently delete '{}' and all data inside.", vault.img.display());
    if !prompt::confirm_name(ctx, &vault.name, &warning)? {
        die!("aborted");
    }

    std::fs::remove_file(&vault.img)?;
    if let Some(kf) = &kf_path {
        if kf.exists() {
            std::fs::remove_file(kf)?;
            logf!(ctx, "  [i] keyfile deleted: {}", kf.display());
        }
    }
    vault.cleanup_mnt_dir();
    logf!(ctx, "[✓] vault '{}' deleted", vault.name);
    Ok(())
}
