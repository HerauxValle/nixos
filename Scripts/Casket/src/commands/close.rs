// &desc: "`cas <vault> close` — unmount and lock the vault. --force also tears down a stuck/orphaned mapper that's neither mounted nor cleanly closeable. Refuses while a `cas exec` session is live (see commands::exec::lockfile) -- unmounting out from under a running sandboxed process is exactly the kind of thing that should never happen silently."
use crate::commands::exec::lockfile;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, force: bool) -> Result<()> {
    if vault.is_mount() && lockfile::is_live(vault) {
        die!("'{}' has a live 'cas exec' session -- wait for it to exit before closing", vault.name);
    }
    if !vault.is_mount() {
        // Without --force this is the common, harmless case (already
        // closed) and it's not worth checking further. With --force,
        // "not mounted" doesn't mean "nothing to do" — a mapper can be
        // left behind, active but unmountable, by a crashed previous
        // run (its backing loop device gone, the crypt target wedged
        // "busy"); is_mount() alone can't tell the two apart, so force
        // always attempts the real teardown and reports what happened.
        if !force || !vault.mapper_dev_exists() {
            logf!(ctx, "[i] '{}' is already closed", vault.name);
            return Ok(());
        }
        logf!(ctx, "[cas] '{}' isn't mounted but has a mapper — force-closing ...", vault.name);
        vault.close_mapper_checked()?;
        logf!(ctx, "[✓] '{}' closed", vault.name);
        return Ok(());
    }
    logf!(ctx, "[cas] closing '{}' ...", vault.name);
    vault.umount();
    if force {
        vault.close_mapper_checked()?;
    } else {
        vault.close_mapper();
    }
    vault.cleanup_mnt_dir();
    logf!(ctx, "[✓] '{}' closed", vault.name);
    Ok(())
}
