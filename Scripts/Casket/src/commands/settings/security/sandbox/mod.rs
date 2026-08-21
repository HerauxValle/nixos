// &desc: "`cas <vault> settings security sandbox enable|disable|state` -- top dispatch for the sandbox feature (Linux namespace isolation for `cas <vault> exec`). Not a plain enable/disable Feature -- namespaces/cgroups/seccomp/rootfs sub-nouns are dispatched from here too, each in its own file, same 'special-cased in settings/mod.rs' shape bruteforceLockout already uses."
use crate::cli_registry::Domain;
use crate::commands::exec::lockfile;
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

pub mod cgroups;
pub mod namespaces;
pub mod network;
pub mod rootfs;
pub mod seccomp;

/// This file's own ids -- `enable`/`disable`/`state` are hand-matched
/// strings in `dispatch()` below rather than resolved through
/// `cli_registry::resolve` (same reason `settings::mod.rs` forwards
/// `security sandbox` here directly instead of walking its own tree:
/// the sub-nouns below need their own multi-level dispatch, not a flat
/// leaf). Registered here purely so `cas debug parse-cli`'s Ignored
/// check knows these three ids *do* have a real handler, even though
/// nothing ever looks them up by number.
pub fn known_ids() -> Vec<&'static str> {
    vec!["1317", "1318", "1319"]
}

inventory::submit! { Domain { known_ids } }

pub fn is_enabled(meta: &Meta) -> bool {
    meta.sandbox_enabled == Some(true)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => enable(ctx, vault, pw),
        Some("disable") => disable(ctx, vault, extra[1..].iter().any(|a| a == "--removeRootfs"), pw),
        Some("state") => state(ctx, vault),
        Some("namespaces") => namespaces::dispatch(ctx, vault, &extra[1..], pw),
        Some("network") => network::dispatch(ctx, vault, &extra[1..], pw),
        Some("rootfs") => rootfs::dispatch(ctx, vault, &extra[1..], pw),
        Some("seccomp") => seccomp::dispatch(ctx, vault, &extra[1..], pw),
        Some("cgroups") => cgroups::dispatch(ctx, vault, &extra[1..], pw),
        _ => die!("usage: cas <vault> settings security sandbox enable|disable [--removeRootfs]|state|namespaces|network|rootfs|seccomp|cgroups ..."),
    }
}

fn enable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.sandbox_enabled = Some(true);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] sandbox enabled for '{}'", vault.name);
    logf!(ctx, "  [i] 'cas {} exec' is now permitted — see 'cas exec --help'", vault.name);
    Ok(())
}

fn disable(ctx: &Ctx, vault: &Vault, remove_rootfs: bool, pw: Option<&str>) -> Result<()> {
    if vault.is_mount() && lockfile::is_live(vault) {
        die!("'{}' has a live 'cas exec' session -- wait for it to exit before disabling sandbox", vault.name);
    }
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;

    // Run before flipping the flag off -- a refusal here (e.g. a
    // `default` rootfs environment still set, same rule
    // `rootfs remove all` itself enforces) should leave sandbox exactly
    // as it was, not disabled-with-leftover-environments requiring
    // re-enabling just to clean up.
    if remove_rootfs {
        if !vault.is_mount() {
            die!("--removeRootfs requires '{}' to be open -- rootfs environments live inside the mounted vault", vault.name);
        }
        // Reuse the passphrase already resolved by the gate_inner call
        // above (if verification ran) so remove_all's own gate_inner
        // call doesn't prompt a second time for the same thing.
        let resolved_pw = verified.as_ref().map(|(p, _)| p.as_str()).or(pw);
        rootfs::remove_all(ctx, vault, resolved_pw)?;
    }

    let mut meta = Meta::read(&vault.img);
    meta.sandbox_enabled = None;
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] sandbox disabled for '{}'", vault.name);
    Ok(())
}

fn state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let width = registry::column_width(&["sandbox"]);
    logf!(ctx, "{}", registry::line("sandbox", is_enabled(&meta), width));
    Ok(())
}
