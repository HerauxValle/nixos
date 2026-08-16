// &desc: "`rootfs rename <old> <new>` -- auto-updates the default symlink if it pointed at <old>, never leaving it dangling (unlike remove, which refuses outright on the default target -- a rename isn't destructive, so carrying the pointer forward is safe)."
use std::fs;

use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::rootfs::{default_target, ensure_dir, set_default, validate_name, RESERVED_NAMES};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let (Some(old), Some(new)) = (extra.first(), extra.get(1)) else {
        die!("usage: cas <vault> settings security sandbox rootfs rename <old> <new>");
    };
    if RESERVED_NAMES.contains(&new.as_str()) {
        die!("'{new}' is a reserved name -- an environment can't be called that");
    }
    validate_name(old)?;
    validate_name(new)?;

    let dir = ensure_dir(vault)?;
    if !dir.join(old).exists() {
        die!("rootfs environment '{old}' doesn't exist -- see 'cas <vault> settings security sandbox rootfs list'");
    }
    if dir.join(new).exists() {
        die!("rootfs environment '{new}' already exists");
    }
    gate_inner(ctx, vault, "sandbox", pw)?;

    // Must check before the rename, not after -- once `old`'s directory
    // is gone, the default symlink (if it pointed at `old`) is
    // dangling, and canonicalize()-based default_target() can no longer
    // resolve it to tell us what it used to point at.
    let was_default = default_target(vault).as_deref() == Some(old.as_str());

    fs::rename(dir.join(old), dir.join(new))?;

    if was_default {
        set_default(vault, Some(new))?;
        logf!(ctx, "[i] default target updated to '{new}'");
    }

    logf!(ctx, "[✓] renamed '{old}' -> '{new}'");
    Ok(())
}
