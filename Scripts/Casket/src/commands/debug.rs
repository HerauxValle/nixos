// &desc: "`cas debug <subcommand>` -- bare top-level dev/introspection command, no vault needed, same shape as `list`/`quit`/`help`. Fully separate from the existing boolean `--debug` flag (which stays exactly what it was: enables tracing during a real vault action) -- sharing the word is cosmetic, not a design coupling. `parse-cli` is the only subcommand today; more can be added the same way as this grows."
use crate::cli_registry::{self, Domain, Resolved};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code5001,
}

impl ActionId {
    fn from_code(s: &str) -> Option<Self> {
        (s == "5001").then_some(ActionId::Code5001)
    }
}

pub fn dispatch(ctx: &Ctx, extra: &[String]) -> Result<()> {
    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    let debug_children = debug_children();
    match cli_registry::resolve(debug_children, &tokens) {
        Resolved::Leaf(node, _consumed) => match node.id.as_deref().and_then(ActionId::from_code) {
            Some(ActionId::Code5001) => parse_cli(ctx),
            None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
        },
        Resolved::Branch(_) | Resolved::NotFound => die!("usage: cas debug parse-cli"),
    }
}

/// Vault top-level single-verb actions (create/open/close/...) and
/// `exec` are registered in `cli/registry.kdl` for documentation/help
/// purposes (so `debug parse-cli`/`cas help` cover them) but were
/// deliberately NOT rewired through `cli_registry::resolve` for
/// dispatch -- they're flat, non-nested commands where routing through
/// the registry buys nothing, and `src/cli.rs`'s top-level match
/// already handles every one of them directly. No handler-domain module
/// owns these ids, hence the small local lists here instead of a
/// `known_ids()` import.
fn vault_top_known_ids() -> Vec<&'static str> {
    vec!["1001", "1002", "1003", "1004", "1005", "1006", "1007", "1008", "1009"]
}

inventory::submit! { Domain { known_ids: vault_top_known_ids } }

fn exec_known_ids() -> Vec<&'static str> {
    vec!["2100"]
}

inventory::submit! { Domain { known_ids: exec_known_ids } }

fn debug_own_known_ids() -> Vec<&'static str> {
    vec!["5001"]
}

inventory::submit! { Domain { known_ids: debug_own_known_ids } }

fn debug_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| cli_registry::get().bare.iter().find(|n| n.name == "debug").map(|n| n.children.clone()).unwrap_or_default())
        .as_slice()
}

/// Dumps the compiled-in CLI registry as ASCII, then an `Ignored:`
/// section (declared ids with no wired Rust handler in any domain) and
/// a `Duplicate:` section (an id claimed by more than one KDL node) --
/// both empty in the normal case, both computed fresh every call so
/// this never gets stale relative to the actual compiled-in tree.
fn parse_cli(ctx: &Ctx) -> Result<()> {
    let reg = cli_registry::get();

    logf!(ctx, "{}", crate::commands::settings::registry::section("bare"));
    let mut tree = String::new();
    cli_registry::render_tree(&reg.bare, "  ", &mut tree);
    logf!(ctx, "{}", tree.trim_end());

    logf!(ctx, "{}", crate::commands::settings::registry::section("vault"));
    let mut tree = String::new();
    cli_registry::render_tree(&reg.vault, "  ", &mut tree);
    logf!(ctx, "{}", tree.trim_end());

    // Every self-registered domain's known-good codes, unioned via
    // inventory -- no domain module path is named here, so adding,
    // moving, or renaming a domain never touches this function. A new
    // domain only needs its own `inventory::submit! { Domain { known_ids } }`
    // next to its own `known_ids()`, wherever it happens to live.
    let known: Vec<&str> = cli_registry::all_known_ids();

    let mut all_ids = Vec::new();
    cli_registry::collect_ids(&reg.bare, &mut all_ids);
    cli_registry::collect_ids(&reg.vault, &mut all_ids);

    let ignored: Vec<&String> = all_ids.iter().filter(|id| !known.contains(&id.as_str())).collect();
    let mut seen = std::collections::HashSet::new();
    let mut duplicates: Vec<&String> = Vec::new();
    for id in &all_ids {
        if !seen.insert(id.as_str()) && !duplicates.iter().any(|d: &&String| d.as_str() == id.as_str()) {
            duplicates.push(id);
        }
    }

    if !ignored.is_empty() {
        logf!(ctx, "");
        logf!(ctx, "[!] Ignored (declared, no wired Rust handler): {}", ignored.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", "));
    }
    if !duplicates.is_empty() {
        logf!(ctx, "");
        logf!(ctx, "[x] Duplicate (claimed by more than one node): {}", duplicates.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", "));
    }
    Ok(())
}
