// &desc: "Module hub and top dispatch for `cas <vault> settings ...` -- home for every persistent per-vault toggle (encryption, 2fa, backup auto, security features, verification requirements), all sharing one enable|disable verb and the gate.rs verification hook."
pub mod backup_auto;
pub mod encryption;
pub mod gate;
pub mod registry;
pub mod security;
pub mod twofa;
pub mod verification;

use crate::cli_registry::Domain;
use crate::cli_registry::{self, Resolved};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::vault::Vault;
use registry::Feature;

/// Settings that are a flat `cas <vault> settings <name> enable|disable`,
/// no category needed.
pub const FLAT_FEATURES: &[Feature] = &[encryption::FEATURE, twofa::FEATURE];

/// This subtree's own flat, position-independent id space -- see
/// `cli/registry.kdl`'s doc comment and `src/cli_registry/mod.rs`'s for
/// the full reasoning (same pattern as
/// `commands::settings::security::sandbox::network`'s `ActionId`).
/// Covers `settings` itself plus `settings security`'s non-sandbox
/// features -- `sandbox` is a different domain's id space, special-cased
/// below rather than resolved through this tree at all.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code1300,
    Code1301,
    Code1302,
    Code1303,
    Code1304,
    Code1305,
    Code1306,
    Code1307,
    Code1308,
    Code1309,
    Code1310,
    Code1311,
    Code1312,
    Code1313,
    Code1314,
    Code1315,
    Code1316,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[
        ("1300", ActionId::Code1300),
        ("1301", ActionId::Code1301),
        ("1302", ActionId::Code1302),
        ("1303", ActionId::Code1303),
        ("1304", ActionId::Code1304),
        ("1305", ActionId::Code1305),
        ("1306", ActionId::Code1306),
        ("1307", ActionId::Code1307),
        ("1308", ActionId::Code1308),
        ("1309", ActionId::Code1309),
        ("1310", ActionId::Code1310),
        ("1311", ActionId::Code1311),
        ("1312", ActionId::Code1312),
        ("1313", ActionId::Code1313),
        ("1314", ActionId::Code1314),
        ("1315", ActionId::Code1315),
        ("1316", ActionId::Code1316),
    ];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    /// Every code this domain knows how to handle -- consulted only by
    /// `cas debug parse-cli` (via `commands::debug::known_ids`, wired up
    /// by whichever agent owns that shared file) to compute the Ignored
    /// list, never by dispatch itself.
    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation --
/// see `commands::debug`.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }

/// Finds `settings`'s own children inside the compiled-in registry tree
/// once. If this ever returns `None`/empty it means `cli/registry.kdl`
/// and this file's hardcoded navigation path have drifted apart -- a
/// build-time/test bug, not something a user can trigger.
fn settings_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| cli_registry::get().vault.iter().find(|n| n.name == "settings").map(|n| n.children.clone()).unwrap_or_default())
        .as_slice()
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    // `sandbox` is a different agent's id space (`security::sandbox`'s
    // own `ActionId`/registry subtree) -- it isn't a node in this
    // domain's fragment of `cli/registry.kdl` at all (see that fragment's
    // trailing comment), so it can never resolve through this tree.
    // Forward straight to the unchanged sandbox dispatcher, same call
    // the old hand-written match here used to make directly.
    if extra.first().map(String::as_str) == Some("security") && extra.get(1).map(String::as_str) == Some("sandbox") {
        return security::sandbox::dispatch(ctx, vault, &extra[2..], pw);
    }

    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(settings_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                // Declared in the KDL but no matching Rust variant --
                // exactly the gap `debug parse-cli`'s Ignored list is
                // for. Refuse cleanly rather than silently no-op.
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..], pw)
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> settings <encryption|2fa|security|verification|backup> ...")
        }
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, rest: &[String], pw: Option<&str>) -> Result<()> {
    match id {
        ActionId::Code1300 => registry::dispatch(FLAT_FEATURES, "encryption", true, ctx, vault, pw),
        ActionId::Code1301 => registry::dispatch(FLAT_FEATURES, "encryption", false, ctx, vault, pw),
        ActionId::Code1302 => registry::state(FLAT_FEATURES, "encryption", ctx, vault),
        ActionId::Code1303 => registry::dispatch(FLAT_FEATURES, "2fa", true, ctx, vault, pw),
        ActionId::Code1304 => registry::dispatch(FLAT_FEATURES, "2fa", false, ctx, vault, pw),
        ActionId::Code1305 => registry::state(FLAT_FEATURES, "2fa", ctx, vault),
        ActionId::Code1306 => backup_auto::dispatch(ctx, vault, rest, pw),
        ActionId::Code1307 => verification_dispatch(ctx, vault, rest, pw),
        ActionId::Code1308 => registry::dispatch(security::FEATURES, "ransomwareProtection", true, ctx, vault, pw),
        ActionId::Code1309 => registry::dispatch(security::FEATURES, "ransomwareProtection", false, ctx, vault, pw),
        ActionId::Code1310 => registry::state(security::FEATURES, "ransomwareProtection", ctx, vault),
        ActionId::Code1311 => registry::dispatch(security::FEATURES, "zeroize", true, ctx, vault, pw),
        ActionId::Code1312 => registry::dispatch(security::FEATURES, "zeroize", false, ctx, vault, pw),
        ActionId::Code1313 => registry::state(security::FEATURES, "zeroize", ctx, vault),
        ActionId::Code1314 => security::bruteforce_lockout::dispatch(ctx, vault, rest, pw),
        ActionId::Code1315 => security::header_offset::dispatch(ctx, vault, rest, pw),
        ActionId::Code1316 => security::header_encryption::dispatch(ctx, vault, rest, pw),
    }
}

/// `settings verification ...` swallows its entire rest-of-argv itself,
/// same shape `backup_auto`/`bruteforceLockout` already used before this
/// system existed -- `<feature>` isn't a fixed set of KDL child nodes,
/// it's whatever string the caller passes (see `gate::GATED_FEATURES`
/// for the common ones, but `verification::dispatch` itself accepts
/// any). `rest` here is `extra` from one token in (past "verification"):
/// `rest[0]` is the feature name or "state", `rest[1]` is the verb or
/// "state" -- unchanged from the original hand-written match's
/// `extra[1]`/`extra[2]` (shifted by exactly the one token this
/// function's caller already consumed).
fn verification_dispatch(ctx: &Ctx, vault: &Vault, rest: &[String], pw: Option<&str>) -> Result<()> {
    if rest.first().map(String::as_str) == Some("state") {
        return verification::state(ctx, vault, None);
    }
    let feature = rest.first().map(String::as_str).unwrap_or("");
    if rest.get(1).map(String::as_str) == Some("state") {
        return verification::state(ctx, vault, Some(feature));
    }
    let enable = parse_verb(rest.get(1))?;
    verification::dispatch(ctx, vault, feature, enable, pw)
}

fn parse_verb(verb: Option<&String>) -> Result<bool> {
    match verb.map(String::as_str) {
        Some("enable") => Ok(true),
        Some("disable") => Ok(false),
        _ => die!("usage: ... enable|disable|state"),
    }
}
