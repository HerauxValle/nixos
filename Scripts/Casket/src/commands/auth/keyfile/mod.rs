// &desc: "Handler modules for `cas <vault> auth keyfile <move|reset|embed|extract|strip|activate>`, plus resolve_current() -- the shared 'find the vault's real keyfile right now' helper every subcommand but extract/strip needs (they operate on an arbitrary carrier, not necessarily the active keyfile). Routing itself lives one level up now, in auth::dispatch (see that file's doc comment for why): cli_registry::resolve walks the whole `auth` subtree -- including these `keyfile` leaves -- in one pass, so a separate `keyfile`-only dispatch layer would just be dead code. Submodules are pub(crate) so auth::dispatch_action can call straight into each handler's unchanged run()."
pub(crate) mod activate;
pub(crate) mod embed;
pub(crate) mod extract;
pub(crate) mod relocate;
pub(crate) mod reset;
pub(crate) mod strip;

use std::path::{Path, PathBuf};

use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::meta::Meta;
use crate::secret::{resolve_keyfile, resolve_lexically};
use crate::vault::Vault;

/// The vault's *current* keyfile, resolved via `--keyfile <path>` if
/// given (the override, same meaning as `open`'s), otherwise the cached
/// path in `Meta` — prompting interactively if that's missing, same as
/// `open` does. Dies if the vault has no keyfile at all (2FA not on).
fn resolve_current(ctx: &Ctx, vault: &Vault, meta: &mut Meta, kf_override: Option<&Path>) -> Result<PathBuf> {
    let Some(cached) = meta.keyfile.clone() else {
        die!(
            "2FA is not enabled on this vault — there's no keyfile to work with\n    Run 'cas {} settings 2fa enable' first.",
            vault.name
        );
    };
    if let Some(p) = kf_override {
        let p = resolve_lexically(p);
        if !p.exists() {
            die!("keyfile not found: {}", p.display());
        }
        return Ok(p);
    }
    resolve_keyfile(ctx, &cached, meta, &vault.img, crate::version::CURRENT)
}
