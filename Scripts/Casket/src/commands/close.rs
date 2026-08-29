// &desc: "`cas <vault> close` — unmount and lock the vault. --force also tears down a stuck/orphaned mapper that's neither mounted nor cleanly closeable. Refuses while a `cas exec` session is live (see commands::exec::lockfile) -- unmounting out from under a running sandboxed process is exactly the kind of thing that should never happen silently."
use crate::commands::exec::lockfile;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::udisks;
use crate::vault::Vault;

/// `create --test` vaults delete their own `.img` right after a clean
/// close -- mirrors `commands::delete`'s own image-removal steps
/// (loop-device teardown before unlink, same ordering/reasoning as
/// there) but never touches a keyfile even if one exists, unlike
/// `delete --removeKeyfile` -- an ephemeral vault deleting a keyfile
/// that might be shared with another, real vault would be exactly the
/// kind of automatic action this should never take.
fn delete_ephemeral(ctx: &Ctx, vault: &Vault) {
    udisks::loop_teardown(&vault.img);
    match std::fs::remove_file(&vault.img) {
        Ok(()) => logf!(ctx, "  [i] --test vault: '{}' deleted", vault.img.display()),
        Err(e) => logf!(ctx, "  [!] --test vault: failed to delete '{}': {e}", vault.img.display()),
    }
}

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
            // A --test vault that was created but never opened never hit
            // is_mount() == true, so the ephemeral-delete path below
            // never ran for it either -- without this, "create --test"
            // followed immediately by "close" (no "open" in between, a
            // very plausible throwaway-test sequence) silently left the
            // .img behind instead of cleaning it up.
            if vault.img.exists() && Meta::read(&vault.img).ephemeral.unwrap_or(false) {
                delete_ephemeral(ctx, vault);
            }
            return Ok(());
        }
        logf!(ctx, "[cas] '{}' isn't mounted but has a mapper — force-closing ...", vault.name);
        vault.close_mapper_checked()?;
        // `create`'s `udisks::loop_setup` registers a loop device for the
        // .img that nothing else ever reuses (`cryptsetup open` manages
        // its own, separate loop internally, torn down with the mapper) --
        // previously only `delete`/an ephemeral vault's auto-delete ever
        // called this, so a real vault's create-time loop leaked forever
        // across every ordinary close, left dangling and unlabeled in
        // udisks/Dolphin until the vault was deleted or the machine
        // rebooted. Best-effort/silent by design (see its own doc
        // comment) -- a no-op here whenever there's nothing left to tear
        // down.
        udisks::loop_teardown(&vault.img);
        logf!(ctx, "[✓] '{}' closed", vault.name);
        if Meta::read(&vault.img).ephemeral.unwrap_or(false) {
            delete_ephemeral(ctx, vault);
        }
        return Ok(());
    }
    logf!(ctx, "[cas] closing '{}' ...", vault.name);
    let ephemeral = Meta::read(&vault.img).ephemeral.unwrap_or(false);
    vault.umount();
    if force {
        vault.close_mapper_checked()?;
    } else {
        vault.close_mapper();
    }
    vault.cleanup_mnt_dir();
    udisks::loop_teardown(&vault.img);
    logf!(ctx, "[✓] '{}' closed", vault.name);
    if ephemeral {
        delete_ephemeral(ctx, vault);
    }
    Ok(())
}
