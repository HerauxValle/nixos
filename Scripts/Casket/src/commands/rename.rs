// &desc: "`cas <vault> rename <newname>` — rename the .img file in place; the vault must be closed."
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, extra: &[String]) -> Result<()> {
    // The original took the *last* word of the whole `cas <vault> rename
    // ...` invocation as the new name, which — since that list always
    // has at least 2 elements ([vault, "rename"]) — meant `cas myvault
    // rename` with no name given silently renamed the vault to
    // "rename.img" instead of erroring. This only ever looks at the
    // rename-specific trailing args, so a missing name is reported
    // properly instead of being misread as the action word.
    let Some(new) = extra.first() else {
        die!("missing new name: cas <vault> rename <newname>");
    };
    if new == &vault.name {
        die!("new name is the same as current name");
    }
    if vault.is_mount() {
        die!("vault is open — close it first: cas {} close", vault.name);
    }
    let new_img = vault.img.with_file_name(format!("{new}.img"));
    if new_img.exists() {
        die!("target already exists: {new}.img");
    }
    logf!(ctx, "[cas] renaming '{}' -> '{new}' ...", vault.name);
    std::fs::rename(&vault.img, &new_img)?;
    logf!(ctx, "[✓] renamed to '{new}'");
    Ok(())
}
