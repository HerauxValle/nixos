// &desc: "`cas <vault> delete [--removeKeyfile] [--shred]` — permanently remove the vault file, after a typed-name confirmation. The keyfile is preserved by default (opt-in to remove it) since it isn't necessarily exclusive to this vault -- nothing here can tell whether some other vault's Meta.keyfile also points at the same file. --shred overwrites the .img in place before unlinking -- best-effort: meaningful on a spinning disk, close to theater on an SSD (TRIM/wear-leveling means the overwrite doesn't hit the same physical cells), so it's opt-in rather than a default."
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

use rand::RngCore;

use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::resolve_lexically;
use crate::vault::Vault;

const SHRED_PASSES: u32 = 3;

fn shred_file(path: &Path) -> std::io::Result<()> {
    let len = path.metadata()?.len();
    let mut f = std::fs::OpenOptions::new().write(true).open(path)?;
    let mut chunk = vec![0u8; 1024 * 1024];
    for _ in 0..SHRED_PASSES {
        f.seek(SeekFrom::Start(0))?;
        let mut remaining = len;
        while remaining > 0 {
            let n = remaining.min(chunk.len() as u64) as usize;
            rand::thread_rng().fill_bytes(&mut chunk[..n]);
            f.write_all(&chunk[..n])?;
            remaining -= n as u64;
        }
        f.sync_all()?;
    }
    Ok(())
}

pub fn run(ctx: &Ctx, vault: &Vault, remove_keyfile: bool, shred: bool) -> Result<()> {
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

    if shred {
        logf!(ctx, "[cas] shredding '{}' ({SHRED_PASSES} passes) ...", vault.name);
        if shred_file(&vault.img).is_err() {
            logf!(ctx, "  [!] shred pass failed — deleting normally instead");
        }
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
