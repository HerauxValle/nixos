// &desc: "Module hub + registry-driven dispatch for `cas <vault> auth ...` -- identity material (passphrase, keyfile) as opposed to settings/ (behavior toggles). `dispatch()` resolves the whole `auth` subtree (passwd plus every keyfile leaf) in one shot via cli_registry::resolve, same pattern as commands::settings::security::sandbox::network -- passwd's old-passphrase prompt + strength/new-pass plumbing (previously special-cased in cli.rs) now happens here, right before calling into the unchanged passwd::run/keyfile handlers."
pub mod keyfile;
pub mod passwd;

use std::path::Path;

use crate::cli_registry::Domain;
use crate::cli_registry::{self, Resolved};
use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::prompt;
use crate::vault::Vault;

/// This subtree's own flat, position-independent id space -- see
/// `cli/registry.kdl`'s doc comment and `src/cli_registry/mod.rs`'s for
/// the full reasoning. Each variant is a bare number, not a semantic
/// name: the meaningful name lives on the handler function it maps to
/// below, never on the id itself.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code1100,
    Code1101,
    Code1102,
    Code1103,
    Code1104,
    Code1105,
    Code1106,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[
        ("1100", ActionId::Code1100),
        ("1101", ActionId::Code1101),
        ("1102", ActionId::Code1102),
        ("1103", ActionId::Code1103),
        ("1104", ActionId::Code1104),
        ("1105", ActionId::Code1105),
        ("1106", ActionId::Code1106),
    ];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    /// Every code this domain knows how to handle -- consulted only by
    /// `cas debug parse-cli` (via the domain's `known_ids` export) to
    /// compute the Ignored list, never by dispatch itself.
    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Finds the `auth` node inside the compiled-in registry tree once. If
/// this ever returns `None` it means `cli/registry.kdl` and this file's
/// hardcoded navigation path have drifted apart -- a build-time/test
/// bug, not something a user can trigger.
fn auth_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| cli_registry::get().vault.iter().find(|n| n.name == "auth").map(|n| n.children.clone()).unwrap_or_default())
        .as_slice()
}

#[allow(clippy::too_many_arguments)]
pub fn dispatch(
    ctx: &Ctx,
    vault: &Vault,
    extra: &[String],
    pw: Option<&str>,
    new_pass: Option<&str>,
    strength: Strength,
    kf_override: Option<&Path>,
) -> Result<()> {
    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(auth_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..], pw, new_pass, strength, kf_override)
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> auth <passwd|keyfile> ...\n    Run 'cas help auth' for details.")
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn dispatch_action(
    ctx: &Ctx,
    vault: &Vault,
    id: ActionId,
    rest: &[String],
    pw: Option<&str>,
    new_pass: Option<&str>,
    strength: Strength,
    kf_override: Option<&Path>,
) -> Result<()> {
    match id {
        ActionId::Code1100 => {
            let old_pw = prompt::get_pw(ctx, pw)?;
            let strength = (strength != Strength::Medium).then_some(strength);
            passwd::run(ctx, vault, &old_pw, new_pass, strength)
        }
        ActionId::Code1101 => {
            let Some(location) = rest.first() else {
                die!("usage: cas <vault> auth keyfile move <location> [--keyfile <current-path>]");
            };
            keyfile::relocate::run(ctx, vault, Path::new(location), kf_override, pw)
        }
        ActionId::Code1102 => keyfile::reset::run(ctx, vault, rest.first().map(Path::new), kf_override, pw),
        ActionId::Code1103 => {
            let Some(carrier) = rest.first() else {
                die!("usage: cas <vault> auth keyfile embed <carrier-file> [--keyfile <current-path>]");
            };
            keyfile::embed::run(ctx, vault, Path::new(carrier), kf_override, pw)
        }
        ActionId::Code1104 => {
            let Some(carrier) = rest.first() else {
                die!("usage: cas <vault> auth keyfile extract <carrier-file> [location]");
            };
            keyfile::extract::run(ctx, vault, Path::new(carrier), rest.get(1).map(Path::new))
        }
        ActionId::Code1105 => {
            let Some(carrier) = rest.first() else {
                die!("usage: cas <vault> auth keyfile strip <carrier-file>");
            };
            keyfile::strip::run(ctx, vault, Path::new(carrier), pw)
        }
        ActionId::Code1106 => {
            let Some(location) = rest.first() else {
                die!("usage: cas <vault> auth keyfile activate <location>");
            };
            keyfile::activate::run(ctx, vault, Path::new(location), pw)
        }
    }
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation -- see
/// `commands::debug`.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }
