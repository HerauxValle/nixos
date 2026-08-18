// &desc: "v6 -> v7: no meta-JSON shape change, no image structure change. Vault::lock_exclusive moved from a `.{name}.lock` sibling dotfile (flock) to an fcntl byte-range lock inside `vault.img` itself (see vault.rs, header/room.rs's LOCK_OFFSET) -- the old sibling file is now dead weight nothing reads or writes, left behind forever by every vault mutated under the pre-fix build. This step deletes it if present."
use crate::ctx::Ctx;
use crate::debugf;
use crate::logf;
use crate::vault::Vault;

use super::Step;

pub const STEP: Step = Step {
    version: 7,
    meta: None,
    layout: Some(migrate_layout),
    requires_new_image: false,
};

fn migrate_layout(ctx: &Ctx, vault: &Vault) {
    let old_lock = vault.img.with_file_name(format!(".{}.lock", vault.name));
    debugf!(ctx, "v7 layout: checking {} exists={}", old_lock.display(), old_lock.exists());
    if !old_lock.exists() {
        return;
    }
    match std::fs::remove_file(&old_lock) {
        Ok(()) => logf!(ctx, "  [i] removed stale lock file {}", old_lock.display()),
        Err(e) => logf!(ctx, "  [!] could not remove stale lock file {}: {e}", old_lock.display()),
    }
}
