// &desc: "`cas <vault> auth keyfile extract <carrier-file> [location]` -- pulls the key bytes out of an embedded carrier and writes them as a standalone raw keyfile. Recovery convenience: if the normal raw keyfile is missing for some reason, this rebuilds it from an embedded copy. Default location is the vault's canonical keyfile path (same convention 2fa enable uses), refusing to overwrite anything already there."
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::keyfile;
use crate::logf;
use crate::secret::resolve_lexically;
use crate::udisks;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, carrier: &Path, location: Option<&Path>) -> Result<()> {
    let carrier = resolve_lexically(carrier);
    if !carrier.exists() {
        die!("carrier file not found: {}", carrier.display());
    }
    if !keyfile::is_embedded(&carrier) {
        die!("no embedded keyfile trailer found in {}", carrier.display());
    }
    let key_bytes = keyfile::read_embedded(&carrier)?;

    let dest = match location {
        Some(loc) => {
            let loc = resolve_lexically(loc);
            if loc.is_dir() {
                loc.join(format!("{}.key", vault.name))
            } else {
                loc
            }
        }
        None => vault.base().join(format!("{}.key", vault.name)),
    };
    if dest.exists() {
        die!("a file already exists at {} — pick a different location", dest.display());
    }

    let mut f = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&dest)?;
    std::io::Write::write_all(&mut f, &key_bytes)?;
    drop(f);
    udisks::chown_to_real_user(&dest)?;

    logf!(ctx, "[✓] keyfile extracted to {}", dest.display());
    logf!(ctx, "    this is a copy — run 'cas {} auth keyfile activate {}' to make it the active one", vault.name, dest.display());
    Ok(())
}
