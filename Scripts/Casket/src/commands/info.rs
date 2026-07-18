// &desc: "`cas <vault> info` — print path, size, open state, 2FA status, and active LUKS slot count."
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::vault::Vault;

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
    let has_2fa = match &meta.keyfile {
        Some(kf) => format!("yes  (keyfile: {kf})"),
        None => "no".to_string(),
    };
    let slots = luks::slot_count(&vault.img);

    logf!(ctx, "\n  vault     {}\n  size      {size_mb} MiB\n  open      {mounted}\n  2fa       {has_2fa}\n  slots     {slots} active\n", vault.img.display());
    Ok(())
}
