// &desc: "`cas <vault> settings security sandbox namespaces set|enable|disable|state` -- which Linux namespaces `exec` isolates. `user` is non-negotiable and always active regardless of what's stored here (see sandbox::exec's own use of this list, not yet wired -- this file only owns storage/validation). Default (nothing stored yet) is every namespace except `net`, offline-by-default being the safer starting posture."
use crate::cli_registry::Domain;
use crate::cli_registry::{self, Resolved};
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

/// This subtree's own flat, position-independent id space -- see
/// `network.rs`'s doc comment (the reference implementation this
/// pattern is copied from) for the full reasoning. Bare numbers only;
/// the meaningful name stays on the handler function, never the id.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code1600,
    Code1601,
    Code1602,
    Code1603,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[
        ("1600", ActionId::Code1600),
        ("1601", ActionId::Code1601),
        ("1602", ActionId::Code1602),
        ("1603", ActionId::Code1603),
    ];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    /// Every code this domain knows how to handle -- consulted only by
    /// `cas debug parse-cli` (via `commands::debug::*_known_ids`) to
    /// compute the Ignored list, never by dispatch itself.
    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Finds the `namespaces` node inside the compiled-in registry tree
/// (`settings -> security -> sandbox -> namespaces`) once. If this ever
/// returns `None` it means `cli/registry.kdl` and this file's hardcoded
/// navigation path have drifted apart -- a build-time/test bug, not
/// something a user can trigger, hence the `expect`.
fn namespaces_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| {
            let path = ["settings", "security", "sandbox", "namespaces"];
            let mut nodes = cli_registry::get().vault.as_slice();
            for name in path {
                nodes = nodes.iter().find(|n| n.name == name).map(|n| n.children.as_slice()).unwrap_or(&[]);
            }
            nodes.to_vec()
        })
        .as_slice()
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation --
/// see `commands::debug`.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }

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
    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(namespaces_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..], pw)
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> settings security sandbox namespaces set|enable|disable <list> | state")
        }
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, rest: &[String], pw: Option<&str>) -> Result<()> {
    match id {
        ActionId::Code1600 => ns_set(ctx, vault, rest, pw),
        ActionId::Code1601 => ns_enable(ctx, vault, rest, pw),
        ActionId::Code1602 => ns_disable(ctx, vault, rest, pw),
        ActionId::Code1603 => state(ctx, vault),
    }
}

fn ns_set(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let Some(raw) = extra.first() else {
        die!("usage: cas <vault> settings security sandbox namespaces set <mount,pid,uts,ipc,user,net>");
    };
    let list = parse_list(raw)?;
    // `disable` already refuses to drop `user`; `set` replaces
    // the whole list outright and had no equivalent check --
    // `set ""` (or any list omitting `user`) silently stored a
    // set that misrepresents what `exec` actually does (`user`
    // is hardcoded on there regardless, see
    // `commands/exec/mod.rs`), so `state` would report an
    // inactive namespace as active. Not an exec-time bypass
    // (exec ignores this field for `user` specifically), but
    // real state corruption worth refusing at the source.
    if !list.iter().any(|n| n == "user") {
        die!("the 'user' namespace can't be excluded -- it's always active regardless of this setting");
    }
    write(ctx, vault, list, pw)
}

fn ns_enable(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let Some(raw) = extra.first() else {
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

fn ns_disable(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let Some(raw) = extra.first() else {
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

fn write(ctx: &Ctx, vault: &Vault, list: Vec<String>, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    let net_newly_active = list.iter().any(|n| n == "net") && !active(&meta).iter().any(|n| n == "net");
    meta.sandbox_namespaces = Some(list.clone());
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] namespaces set to: {}", list.join(", "));
    if net_newly_active {
        logf!(ctx, "  [!] 'net' isolation only brings up loopback inside the sandbox --");
        logf!(ctx, "      there is no route out (no veth/NAT). 'exec' sessions will have no");
        logf!(ctx, "      internet or LAN access at all, only 127.0.0.1/localhost.");
    }
    Ok(())
}

fn state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let width = registry::column_width(&["namespaces"]);
    logf!(ctx, "  {}", registry::kv_line("namespaces", &active(&meta).join(","), width));
    Ok(())
}
