// &desc: "`cas <vault> delete [--removeKeyfile]` — permanently remove the vault file, after a typed-name confirmation. The keyfile is preserved by default (opt-in to remove it) since it isn't necessarily exclusive to this vault -- nothing here can tell whether some other vault's Meta.keyfile also points at the same file."
use std::path::Path;

use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::resolve_lexically;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, remove_keyfile: bool) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let meta = Meta::read(&vault.img);
    // Best-effort only: deleting the vault image never needs the
    // keyfile's actual bytes (nothing here decrypts anything), just its
    // real on-disk path so the keyfile itself can be unlinked afterward.
    // Unlike `open`/`toggle`, this deliberately does NOT fall back to
    // keyfile_mount.rs's raw debugfs block-read for an unmounted
    // removable drive — that path only ever stages a throwaway copy of
    // the bytes into a temp file, which has no bearing on the real file
    // living on the drive, so removing it would accomplish nothing.
    // Vault deletion always proceeds either way; a keyfile that can't be
    // found here (drive not mounted, moved, already gone) is just left
    // for the user to clean up by hand instead of blocking on a prompt.
    let kf_path = meta.keyfile.as_deref().map(Path::new).map(resolve_lexically);

    let warning = format!("This will permanently delete '{}' and all data inside.", vault.img.display());
    if !prompt::confirm_name(ctx, &vault.name, &warning)? {
        die!("aborted");
    }

    std::fs::remove_file(&vault.img)?;
    match &kf_path {
        Some(kf) if !remove_keyfile => {
            logf!(ctx, "  [i] keyfile preserved: {}", kf.display());
            logf!(ctx, "      it may be shared with other vaults — pass --removeKeyfile to delete it too");
        }
        Some(kf) if kf.exists() => {
            std::fs::remove_file(kf)?;
            logf!(ctx, "  [i] keyfile deleted: {}", kf.display());
        }
        Some(kf) => {
            logf!(ctx, "  [!] keyfile not found at {} (drive unmounted/moved?) — remove it yourself if it still exists", kf.display());
        }
        None => {}
    }
    vault.cleanup_mnt_dir();
    logf!(ctx, "[✓] vault '{}' deleted", vault.name);
    Ok(())
}
