// &desc: "v1 -> v2: converts `.casket/` from a plain directory (every vault created before the sandbox feature) into a real btrfs subvolume, so a parent-level snapshot automatically skips its contents. btrfs can't convert a directory to a subvolume in place, so this creates a new subvolume alongside it, migrates the old directory's contents in, then swaps names. Idempotent: a no-op once `.casket/` is already a subvolume."
use std::fs;
use std::path::Path;

use crate::btrfs;
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::vault::Vault;

use super::Step;

pub const STEP: Step = Step {
    version: 2,
    meta: None,
    layout: Some(migrate_layout),
};

fn migrate_layout(ctx: &Ctx, vault: &Vault) {
    let casket_dir = vault.casket_dir();
    if !casket_dir.exists() {
        // Nothing to convert yet — a fresh vault that's never used
        // `.casket/` at all. It'll be created as a subvolume directly
        // by whichever feature first needs it.
        return;
    }
    if btrfs::is_subvolume(&casket_dir) {
        return; // already migrated
    }
    if let Err(e) = convert(&casket_dir) {
        logf!(ctx, "  [!] could not convert .casket/ to a subvolume: {e}");
        return;
    }
    logf!(ctx, "  [i] migrated .casket/ to a real btrfs subvolume");
}

fn convert(casket_dir: &Path) -> Result<()> {
    let staging = casket_dir.parent().expect("casket_dir has a parent (the vault mount root)").join(".casket-migrate-staging");
    if staging.exists() {
        fs::remove_dir_all(&staging)?;
    }
    btrfs::subvolume_create(&staging)?;
    migrate_contents(casket_dir, &staging)?;

    // Preserve the original directory's ownership/mode on the new
    // subvolume before swapping it into place — ransomwareProtection's
    // apply_ownership only runs on toggle/open, not mid-migration.
    let meta = fs::metadata(casket_dir)?;
    fs::set_permissions(&staging, meta.permissions())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        std::os::unix::fs::chown(&staging, Some(meta.uid()), Some(meta.gid()))?;
    }

    // Everything under `casket_dir` has now either been renamed (whole
    // subvolumes) or copied (plain files/dirs) into `staging` — the
    // original tree is safe to remove. Renaming a subvolume itself at
    // the parent-directory level (not its individual contents) is a
    // normal, supported rename, same as swapping `staging` into place.
    fs::remove_dir_all(casket_dir)?;
    fs::rename(&staging, casket_dir)?;
    Ok(())
}

/// Recursively re-creates `src`'s tree under `dest` (which must already
/// exist as a subvolume or plain directory). Any `src` entry that's
/// itself a real btrfs subvolume — e.g. an individual snapshot under
/// `.casket/snapshots/<name>` — is relocated whole via a single
/// `rename()`, never walked into. That matters because `backup create`'s
/// snapshots are full snapshots of the *entire* vault mount, including
/// `.casket/` itself at the time — so a snapshot's own internal tree
/// recursively contains another (older) copy of `.casket/snapshots/...`,
/// arbitrarily deep after enough auto-backups. A blind recursive copy
/// (e.g. `cp -a`) walks straight into that self-nested structure and
/// eventually hits a read-only snapshot subvolume it can't write around.
/// Treating each subvolume as an opaque unit sidesteps the nesting
/// entirely — its internals are never touched, just relocated.
fn migrate_contents(src: &Path, dest: &Path) -> Result<()> {
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let name = entry.file_name();
        let dest_path = dest.join(&name);
        let src_path = entry.path();
        let file_type = entry.file_type()?;

        if file_type.is_dir() && btrfs::is_subvolume(&src_path) {
            // A read-only subvolume (every backup snapshot is created
            // read-only) can't be the source of a rename at all until
            // its `ro` property is temporarily cleared — restored
            // immediately after on the new location, so the relocated
            // snapshot ends up exactly as protected as it started.
            let was_readonly = btrfs::is_readonly(&src_path);
            if was_readonly {
                btrfs::set_readonly(&src_path, false)?;
            }
            match fs::rename(&src_path, &dest_path) {
                Ok(()) => {
                    if was_readonly {
                        btrfs::set_readonly(&dest_path, true)?;
                    }
                }
                Err(e) => {
                    if was_readonly {
                        let _ = btrfs::set_readonly(&src_path, true);
                    }
                    return Err(e.into());
                }
            }
        } else if file_type.is_dir() {
            fs::create_dir(&dest_path)?;
            migrate_contents(&src_path, &dest_path)?;
            let meta = fs::metadata(&src_path)?;
            fs::set_permissions(&dest_path, meta.permissions())?;
        } else {
            fs::copy(&src_path, &dest_path)?;
        }
    }
    Ok(())
}
