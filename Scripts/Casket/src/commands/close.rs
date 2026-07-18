// &desc: "`cas <vault> close` — unmount and lock the vault."
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault) -> Result<()> {
    if !vault.is_mount() {
        logf!(ctx, "[i] '{}' is already closed", vault.name);
        return Ok(());
    }
    logf!(ctx, "[cas] closing '{}' ...", vault.name);
    vault.umount();
    vault.close_mapper();
    vault.cleanup_mnt_dir();
    logf!(ctx, "[✓] '{}' closed", vault.name);
    Ok(())
}
