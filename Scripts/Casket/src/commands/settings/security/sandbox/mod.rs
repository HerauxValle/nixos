// &desc: "`cas <vault> settings security sandbox enable|disable|state` -- top dispatch for the sandbox feature (Linux namespace isolation for `cas <vault> exec`). Not a plain enable/disable Feature -- namespaces/cgroups/seccomp/rootfs sub-nouns are dispatched from here too, each in its own file, same 'special-cased in settings/mod.rs' shape bruteforceLockout/fileIntegrity already use."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

pub mod namespaces;

pub fn is_enabled(meta: &Meta) -> bool {
    meta.sandbox_enabled == Some(true)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => enable(ctx, vault, pw),
        Some("disable") => disable(ctx, vault, pw),
        Some("state") => state(ctx, vault),
        Some("namespaces") => namespaces::dispatch(ctx, vault, &extra[1..], pw),
        _ => die!("usage: cas <vault> settings security sandbox enable|disable|state|namespaces ..."),
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

fn disable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
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
