// &desc: "`cas <vault> auth keyfile strip <carrier-file>` -- the opposite of embed: removes an embedded trailer, restoring the carrier to its original (pre-embed) content. Requires typed confirmation if the carrier is the vault's ACTIVE keyfile, since that would remove the only copy of the key material cas knows about."
use std::path::Path;

use crate::commands::settings::gate::gate;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::keyfile;
use crate::logf;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::resolve_lexically;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, carrier: &Path, pw: Option<&str>) -> Result<()> {
    let carrier = resolve_lexically(carrier);
    if !carrier.exists() {
        die!("carrier file not found: {}", carrier.display());
    }
    if !keyfile::is_embedded(&carrier) {
        die!("no embedded keyfile trailer found in {} — nothing to strip", carrier.display());
    }

    let meta = Meta::read(&vault.img);
    let is_active = meta
        .keyfile
        .as_deref()
        .map(|cached| resolve_lexically(Path::new(cached)) == carrier)
        .unwrap_or(false);

    if is_active {
        gate(ctx, vault, "keyfileStrip", pw)?;
        let warning = format!(
            "'{}' is the ACTIVE keyfile for '{}' — stripping it removes the only copy of the key material cas knows about here. Make sure it's backed up elsewhere first.",
            carrier.display(),
            vault.name
        );
        if !prompt::confirm_name(ctx, &vault.name, &warning)? {
            die!("aborted");
        }
    }

    keyfile::strip_embedded(&carrier)?;
    logf!(ctx, "[✓] embedded keyfile removed from {} — file restored to its original contents", carrier.display());
    if is_active {
        logf!(ctx, "  [!] this vault has no other keyfile on record — 'cas {} open' will fail until you activate or restore one", vault.name);
    }
    Ok(())
}
