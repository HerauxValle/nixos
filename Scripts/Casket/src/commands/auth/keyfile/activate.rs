// &desc: "`cas <vault> auth keyfile activate <location>` -- points the vault at a different file (raw or embedded, auto-detected) as its keyfile, WITHOUT touching the LUKS slot: this only makes sense for a copy/relocation of the exact same key bytes, so it verifies the passphrase + that file actually unlocks the vault before committing, and dies untouched if it doesn't."
use std::path::Path;

use crate::commands::settings::gate::gate_pw;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::keyfile;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::secret::{combined_secret, resolve_lexically};
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, location: &Path, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault is open — close it first:  cas {} close", vault.name);
    }

    let location = resolve_lexically(location);
    if !location.exists() {
        die!("keyfile not found: {}", location.display());
    }

    let mut meta = Meta::read(&vault.img);
    if meta.keyfile.is_none() {
        die!(
            "2FA is not enabled on this vault — there's no keyfile slot to activate one into\n    Run 'cas {} settings 2fa enable' first.",
            vault.name
        );
    }
    let pw = gate_pw(ctx, vault, "keyfileActivate", pw)?;

    let key_bytes = keyfile::read_bytes(&location)?;
    let candidate = combined_secret(&pw, &key_bytes);

    Meta::strip(&vault.img)?;
    let ok = luks::test(&vault.img, &candidate);
    meta.write(&vault.img)?;
    if !ok {
        die!("that passphrase + keyfile combination doesn't unlock this vault — nothing changed");
    }

    meta.keyfile = Some(location.to_string_lossy().into_owned());
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] '{}' is now the active keyfile for '{}'", location.display(), vault.name);
    Ok(())
}
