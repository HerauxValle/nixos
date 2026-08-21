// &desc: "`cas <vault> auth keyfile embed <carrier-file>` -- appends the active keyfile's raw key bytes as a trailer onto any file, any extension, without disturbing its existing content. If the active keyfile is itself embedded, extracts just the key payload first, never nesting a trailer inside a trailer. Doesn't activate the copy -- that's a separate deliberate step."
use std::path::Path;

use crate::commands::settings::gate::gate;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::keyfile;
use crate::logf;
use crate::meta::Meta;
use crate::secret::resolve_lexically;
use crate::udisks;
use crate::vault::Vault;

use super::resolve_current;

pub fn run(ctx: &Ctx, vault: &Vault, carrier: &Path, kf_override: Option<&Path>, pw: Option<&str>) -> Result<()> {
    let mut meta = Meta::read(&vault.img);
    let current = resolve_current(ctx, vault, &mut meta, kf_override)?;
    gate(ctx, vault, "keyfileEmbed", pw)?;

    let carrier = resolve_lexically(carrier);
    if !carrier.exists() {
        die!("carrier file not found: {}\n    (embed writes into an existing file — create it first)", carrier.display());
    }
    if carrier.metadata()?.len() == 0 {
        die!("refusing to embed into an empty file: {}", carrier.display());
    }
    if carrier == current {
        die!("carrier is the active keyfile itself — pick a different file");
    }

    let key_bytes = keyfile::read_bytes(&current)?;
    keyfile::write_embedded(&carrier, &key_bytes)?;
    udisks::chown_to_real_user(&carrier)?;
    logf!(ctx, "[✓] keyfile embedded into {}", carrier.display());
    logf!(ctx, "    this is a copy — the active keyfile is still {}", current.display());
    logf!(ctx, "    run 'cas {} auth keyfile activate {}' to switch to it", vault.name, carrier.display());
    Ok(())
}
