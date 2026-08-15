// &desc: "`cas <vault> settings security sandbox namespaces set|enable|disable|state` -- which Linux namespaces `exec` isolates. `user` is non-negotiable and always active regardless of what's stored here (see sandbox::exec's own use of this list, not yet wired -- this file only owns storage/validation). Default (nothing stored yet) is every namespace except `net`, offline-by-default being the safer starting posture."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

pub const ALL: &[&str] = &["mount", "pid", "uts", "ipc", "user", "net"];

/// Every namespace except `net` -- the built-in default when a vault
/// has never explicitly set this.
pub fn default_set() -> Vec<String> {
    ALL.iter().filter(|n| **n != "net").map(|s| s.to_string()).collect()
}

pub fn active(meta: &Meta) -> Vec<String> {
    meta.sandbox_namespaces.clone().unwrap_or_else(default_set)
}

fn parse_list(raw: &str) -> Result<Vec<String>> {
    let mut out = Vec::new();
    for token in raw.split(',').map(str::trim).filter(|s| !s.is_empty()) {
        if !ALL.contains(&token) {
            die!("unknown namespace '{token}' -- expected one of: {}", ALL.join(", "));
        }
        if !out.contains(&token.to_string()) {
            out.push(token.to_string());
        }
    }
    out.sort();
    Ok(out)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("set") => {
            let Some(raw) = extra.get(1) else {
                die!("usage: cas <vault> settings security sandbox namespaces set <mount,pid,uts,ipc,user,net>");
            };
            let list = parse_list(raw)?;
            write(ctx, vault, list, pw)
        }
        Some("enable") => {
            let Some(raw) = extra.get(1) else {
                die!("usage: cas <vault> settings security sandbox namespaces enable <list>");
            };
            let adding = parse_list(raw)?;
            let mut current = active(&Meta::read(&vault.img));
            for n in adding {
                if !current.contains(&n) {
                    current.push(n);
                }
            }
            current.sort();
            write(ctx, vault, current, pw)
        }
        Some("disable") => {
            let Some(raw) = extra.get(1) else {
                die!("usage: cas <vault> settings security sandbox namespaces disable <list>");
            };
            let removing = parse_list(raw)?;
            if removing.iter().any(|n| n == "user") {
                die!("the 'user' namespace can't be disabled -- it's always active regardless of this setting");
            }
            let mut current = active(&Meta::read(&vault.img));
            current.retain(|n| !removing.contains(n));
            write(ctx, vault, current, pw)
        }
        Some("state") => state(ctx, vault),
        _ => die!("usage: cas <vault> settings security sandbox namespaces set|enable|disable <list> | state"),
    }
}

fn write(ctx: &Ctx, vault: &Vault, list: Vec<String>, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.sandbox_namespaces = Some(list.clone());
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] namespaces set to: {}", list.join(", "));
    Ok(())
}

fn state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let width = registry::column_width(&["namespaces"]);
    logf!(ctx, "  {}", registry::kv_line("namespaces", &active(&meta).join(","), width));
    Ok(())
}
