// &desc: "Dispatch for `cas <vault> auth keyfile <move|reset|embed|extract|strip|activate>`, plus resolve_current() -- the shared 'find the vault's real keyfile right now' helper every subcommand but extract/strip needs (they operate on an arbitrary carrier, not necessarily the active keyfile)."
mod activate;
mod embed;
mod extract;
mod relocate;
mod reset;
mod strip;

use std::path::{Path, PathBuf};

use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::meta::Meta;
use crate::secret::{resolve_keyfile, resolve_lexically};
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], kf_override: Option<&Path>, pw: Option<&str>) -> Result<()> {
    let sub = extra.first().map(String::as_str).unwrap_or("");
    let arg = extra.get(1).map(Path::new);
    let arg2 = extra.get(2).map(Path::new);

    match sub {
        "move" => {
            let Some(location) = arg else {
                die!("usage: cas <vault> auth keyfile move <location> [--keyfile <current-path>]");
            };
            relocate::run(ctx, vault, location, kf_override, pw)
        }
        "reset" => reset::run(ctx, vault, arg, kf_override, pw),
        "embed" => {
            let Some(carrier) = arg else {
                die!("usage: cas <vault> auth keyfile embed <carrier-file> [--keyfile <current-path>]");
            };
            embed::run(ctx, vault, carrier, kf_override, pw)
        }
        "extract" => {
            let Some(carrier) = arg else {
                die!("usage: cas <vault> auth keyfile extract <carrier-file> [location]");
            };
            extract::run(ctx, vault, carrier, arg2)
        }
        "strip" => {
            let Some(carrier) = arg else {
                die!("usage: cas <vault> auth keyfile strip <carrier-file>");
            };
            strip::run(ctx, vault, carrier, pw)
        }
        "activate" => {
            let Some(location) = arg else {
                die!("usage: cas <vault> auth keyfile activate <location>");
            };
            activate::run(ctx, vault, location, pw)
        }
        _ => die!("usage: cas <vault> auth keyfile <move|reset|embed|extract|strip|activate> ...\n    Run 'cas help auth' for details."),
    }
}

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
    resolve_keyfile(ctx, &cached, meta, &vault.img)
}
