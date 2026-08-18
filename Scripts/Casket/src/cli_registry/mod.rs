// &desc: "Generic KDL-tree infrastructure for cli/registry.kdl and cli/codes.kdl -- parsing, navigation, and the Ignored/Duplicate consistency check `debug parse-cli` surfaces. Domain-agnostic on purpose: this module knows nothing about vaults, sandboxes, or networking, only how to walk a tree of named nodes with optional ids/help/args/flags. Each consuming module (e.g. commands::settings::security::sandbox::network) owns its own small ActionId enum and match -- see that file's doc comment for why one flat enum across every domain would defeat the whole point of compile-time exhaustiveness checking."
use std::collections::HashMap;
use std::sync::OnceLock;

use kdl::{KdlDocument, KdlNode};

const REGISTRY_KDL: &str = include_str!("../../cli/registry.kdl");
const CODES_KDL: &str = include_str!("../../cli/codes.kdl");

#[derive(Debug, Clone)]
pub struct ArgSpec {
    pub name: String,
    pub ty: String,
    pub help: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FlagSpec {
    pub name: String,
    pub ty: String,
    pub values: Option<Vec<String>>,
    pub default: Option<String>,
    pub help: Option<String>,
}

/// One node in the tree -- a branch (has `children`, no `id`) or a leaf
/// (has `id`, the raw string as written in the KDL; whether it actually
/// resolves to a real Rust handler is for the consuming domain's own
/// `ActionId::from_code` to decide, not this module).
#[derive(Debug, Clone)]
pub struct TreeNode {
    pub name: String,
    pub id: Option<String>,
    pub help: Option<String>,
    pub args: Vec<ArgSpec>,
    pub flags: Vec<FlagSpec>,
    pub children: Vec<TreeNode>,
}

pub struct Registry {
    pub bare: Vec<TreeNode>,
    pub vault: Vec<TreeNode>,
    /// id -> label, from cli/codes.kdl. Only consulted for display
    /// (`debug parse-cli`, `--help`, doc generation) -- dispatch never
    /// reads this.
    pub codes: HashMap<String, String>,
}

pub fn get() -> &'static Registry {
    static REGISTRY: OnceLock<Registry> = OnceLock::new();
    REGISTRY.get_or_init(|| {
        let doc: KdlDocument = REGISTRY_KDL.parse().expect("cli/registry.kdl failed to parse -- this is a compiled-in file, a parse failure here is a build-time bug, not a user error");
        let mut bare = Vec::new();
        let mut vault = Vec::new();
        for top in doc.nodes() {
            let target = match top.name().value() {
                "bare" => &mut bare,
                "vault" => &mut vault,
                _ => continue,
            };
            if let Some(children) = top.children() {
                for node in children.nodes() {
                    if let Some(t) = node_to_tree(node) {
                        target.push(t);
                    }
                }
            }
        }
        let codes = parse_codes();
        assert_no_duplicate_ids(&bare, &vault);
        Registry { bare, vault, codes }
    })
}

/// A duplicate `id` is worse than an Ignored one: dispatch keys purely
/// on the id string, so two nodes claiming the same id doesn't fail
/// cleanly the way an unwired id does -- the second node would just
/// silently alias onto whatever handler the first one already points
/// to, running code unrelated to what the node's own name/help claims
/// it does. `debug parse-cli` surfaces this for on-demand inspection,
/// but that's advisory only unless something actually enforces it --
/// this does, at the one point every dispatch path already goes
/// through (`Registry::get()`'s first call), so a colliding id fails
/// loud immediately on next use instead of only being caught by
/// someone thinking to run the debug command.
fn assert_no_duplicate_ids(bare: &[TreeNode], vault: &[TreeNode]) {
    let mut all = Vec::new();
    collect_ids(bare, &mut all);
    collect_ids(vault, &mut all);
    let mut seen = std::collections::HashSet::new();
    for id in &all {
        assert!(seen.insert(id.as_str()), "cli/registry.kdl: id \"{id}\" is claimed by more than one node -- run 'cas debug parse-cli' to find them, then fix before anything can dispatch safely");
    }
}

fn parse_codes() -> HashMap<String, String> {
    let doc: KdlDocument = CODES_KDL.parse().expect("cli/codes.kdl failed to parse");
    let mut map = HashMap::new();
    for node in doc.nodes() {
        if node.name().value() != "code" {
            continue;
        }
        let Some(id) = node.entries().iter().find(|e| e.name().is_none()).and_then(|e| e.value().as_string()) else {
            continue;
        };
        let label = get_prop(node, "label").unwrap_or_default();
        map.insert(id.to_string(), label);
    }
    map
}

fn node_to_tree(node: &KdlNode) -> Option<TreeNode> {
    if node.name().value() != "action" {
        return None;
    }
    let name = node.entries().iter().find(|e| e.name().is_none()).and_then(|e| e.value().as_string())?.to_string();
    let id = get_prop(node, "id");
    let help = get_prop(node, "help");
    let mut args = Vec::new();
    let mut flags = Vec::new();
    let mut children = Vec::new();
    if let Some(doc) = node.children() {
        for child in doc.nodes() {
            match child.name().value() {
                "action" => {
                    if let Some(t) = node_to_tree(child) {
                        children.push(t);
                    }
                }
                "arg" => args.push(parse_arg(child)),
                "flag" => flags.push(parse_flag(child)),
                _ => {}
            }
        }
    }
    Some(TreeNode { name, id, help, args, flags, children })
}

fn parse_arg(node: &KdlNode) -> ArgSpec {
    let name = node.entries().iter().find(|e| e.name().is_none()).and_then(|e| e.value().as_string()).unwrap_or("").to_string();
    ArgSpec { name, ty: get_prop(node, "type").unwrap_or_default(), help: get_prop(node, "help") }
}

fn parse_flag(node: &KdlNode) -> FlagSpec {
    let name = node.entries().iter().find(|e| e.name().is_none()).and_then(|e| e.value().as_string()).unwrap_or("").to_string();
    let values = get_prop(node, "values").map(|v| v.split(',').map(str::to_string).collect());
    FlagSpec { name, ty: get_prop(node, "type").unwrap_or_default(), values, default: get_prop(node, "default"), help: get_prop(node, "help") }
}

fn get_prop(node: &KdlNode, key: &str) -> Option<String> {
    node.entries().iter().find(|e| e.name().map(|n| n.value()) == Some(key)).and_then(|e| e.value().as_string()).map(str::to_string)
}

pub enum Resolved<'a> {
    /// Reached a node with an `id` -- `tokens[consumed..]` is whatever
    /// argv is left for the handler's own arg/flag parsing (unchanged
    /// from before this system existed).
    Leaf(&'a TreeNode, usize),
    /// Ran out of tokens on a node with no `id` -- a branch, list its
    /// children (used by `--help`/`debug parse-cli` navigation).
    Branch(&'a TreeNode),
    NotFound,
}

/// Walks `tokens` against `nodes`' names level by level. Pure name
/// matching -- nothing here knows or cares what an `id` maps to in
/// Rust, that's the caller's job once it has a `Leaf`.
pub fn resolve<'a>(nodes: &'a [TreeNode], tokens: &[&str]) -> Resolved<'a> {
    let mut current = nodes;
    let mut node: Option<&TreeNode> = None;
    let mut consumed = 0;
    // Tracks whether the walk stopped because a token didn't match any
    // child name (real misuse -- an unknown subaction/typo), as opposed
    // to simply running out of tokens (a legitimate ancestor lookup, or
    // a leaf that intentionally owns the rest of argv as its own
    // args/flags). Only matters for the Branch case below: a Leaf
    // breaks the loop deliberately via the id check, never via this
    // path, so leaf handlers keep reading `rest` exactly as before.
    let mut mismatched = false;
    for tok in tokens {
        match current.iter().find(|n| n.name == *tok) {
            Some(n) => {
                node = Some(n);
                current = &n.children;
                consumed += 1;
            }
            None => {
                mismatched = true;
                break;
            }
        }
        if node.map(|n| n.id.is_some()).unwrap_or(false) {
            break;
        }
    }
    match node {
        Some(n) if n.id.is_some() => Resolved::Leaf(n, consumed),
        Some(n) if mismatched => Resolved::NotFound,
        Some(n) => Resolved::Branch(n),
        None => Resolved::NotFound,
    }
}

/// Renders `nodes` as an ASCII tree, same style as `docs/cli-layout.md`.
pub fn render_tree(nodes: &[TreeNode], prefix: &str, out: &mut String) {
    for (i, node) in nodes.iter().enumerate() {
        let last = i == nodes.len() - 1;
        let branch = if last { "└── " } else { "├── " };
        let help = node.help.as_deref().unwrap_or("");
        out.push_str(&format!("{prefix}{branch}{}{}\n", node.name, if help.is_empty() { String::new() } else { format!("  -- {help}") }));
        let child_prefix = format!("{prefix}{}", if last { "    " } else { "│   " });
        render_tree(&node.children, &child_prefix, out);
    }
}

/// One domain's self-registration: just its `known_ids` fn pointer.
/// Submitted via `inventory::submit!` at each domain module's own
/// definition site (see e.g. `commands::settings::security::sandbox::
/// network`) -- nothing outside that module ever names its path. This
/// is what lets `debug parse-cli`'s Ignored check, and any future
/// consumer that needs "every known id", discover every domain
/// automatically instead of importing them one by one into a hand-
/// maintained list. Moving, renaming, or nesting a domain module
/// differently never requires touching this file or any aggregator --
/// the `submit!` travels with the module wherever it lives.
pub struct Domain {
    pub known_ids: fn() -> Vec<&'static str>,
}
inventory::collect!(Domain);

/// Every id known to every self-registered domain, unioned. Domains
/// with no owning Rust module (the flat vault-top-level verbs and
/// `exec`, both dispatched directly in `cli.rs` rather than through
/// this registry) self-register too, from wherever their ids are
/// actually declared -- see `commands::debug`'s own `submit!` for those.
pub fn all_known_ids() -> Vec<&'static str> {
    inventory::iter::<Domain>().flat_map(|d| (d.known_ids)()).collect()
}

/// Every raw `id` string found anywhere in `nodes`, walked recursively --
/// used by `debug parse-cli` to compute Ignored (against a domain's own
/// known-good codes) and Duplicate (ids appearing more than once).
pub fn collect_ids(nodes: &[TreeNode], out: &mut Vec<String>) {
    for node in nodes {
        if let Some(id) = &node.id {
            out.push(id.clone());
        }
        collect_ids(&node.children, out);
    }
}
