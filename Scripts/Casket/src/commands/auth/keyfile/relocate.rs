// &desc: "`cas <vault> auth keyfile move <location>` -- relocates the active keyfile (copy, verify, then delete original; never a bare rename since the target is often a different filesystem like a removable drive). Preserves raw/embedded form as-is."
use std::path::{Path, PathBuf};

use crate::commands::settings::gate::gate;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::secret::resolve_lexically;
use crate::udisks;
use crate::vault::Vault;

use super::resolve_current;

pub fn run(ctx: &Ctx, vault: &Vault, location: &Path, kf_override: Option<&Path>, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let mut meta = Meta::read(&vault.img);
    let current = resolve_current(ctx, vault, &mut meta, kf_override)?;
    gate(ctx, vault, "keyfileMove", pw)?;

    let dest = target_path(&current, location);
    if dest == current {
        die!("already at that location");
    }
    if dest.exists() {
        die!("a file already exists at {} — pick a different location", dest.display());
    }

    std::fs::copy(&current, &dest)?;
    if std::fs::read(&dest)? != std::fs::read(&current)? {
        let _ = std::fs::remove_file(&dest);
        die!("copy verification failed — original left untouched at {}", current.display());
    }
    udisks::chown_to_real_user(&dest)?;
    std::fs::remove_file(&current)?;

    meta.keyfile = Some(dest.to_string_lossy().into_owned());
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] keyfile moved to {}", dest.display());
    Ok(())
}

fn target_path(current: &Path, location: &Path) -> PathBuf {
    let location = resolve_lexically(location);
    if location.is_dir() {
        location.join(current.file_name().unwrap_or_default())
    } else {
        location
    }
}
