// &desc: "`cas <vault> settings security sandbox network internet enable|disable|state` -- opt-in real outbound connectivity for exec's 'net' namespace, separate from `namespaces enable net` itself (see sandbox::network's own doc comment for why the two are split: 'net' alone is always safe/contained loopback-only, this is the part that actually mutates the host's routing/NAT)."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::commands::settings::security::sandbox::namespaces;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("internet") => match extra.get(1).map(String::as_str) {
            Some("enable") => enable(ctx, vault, pw),
            Some("disable") => disable(ctx, vault, pw),
            Some("state") => state(ctx, vault),
            _ => die!("usage: cas <vault> settings security sandbox network internet enable|disable|state"),
        },
        _ => die!("usage: cas <vault> settings security sandbox network internet enable|disable|state"),
    }
}

pub fn is_enabled(meta: &Meta) -> bool {
    meta.sandbox_internet == Some(true)
}

fn enable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let meta = Meta::read(&vault.img);
    if !namespaces::active(&meta).iter().any(|n| n == "net") {
        die!(
            "'internet' requires the 'net' namespace to be active first -- run 'cas {} settings security sandbox namespaces enable net'",
            vault.name
        );
    }
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = meta;
    meta.sandbox_internet = Some(true);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] internet access enabled for '{}' sandboxed exec sessions", vault.name);
    logf!(ctx, "  [!] this sets up a real veth pair + host NAT (MASQUERADE) rule for the");
    logf!(ctx, "      duration of each 'exec' session -- a step up from the isolated,");
    logf!(ctx, "      contained loopback-only default. Torn down automatically when 'exec'");
    logf!(ctx, "      exits (and swept on next use if a previous session crashed).");
    Ok(())
}

fn disable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.sandbox_internet = None;
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] internet access disabled for '{}' -- 'exec' sessions are back to loopback-only", vault.name);
    Ok(())
}

fn state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let width = registry::column_width(&["internet"]);
    logf!(ctx, "  {}", registry::line("internet", is_enabled(&meta), width));
    Ok(())
}
