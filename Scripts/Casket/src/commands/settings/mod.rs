// &desc: "Module hub and top dispatch for `cas <vault> settings ...` -- home for every persistent per-vault toggle (encryption, 2fa, backup auto, security features, verification requirements), all sharing one enable|disable verb and the gate.rs verification hook."
pub mod backup_auto;
pub mod encryption;
pub mod gate;
pub mod registry;
pub mod security;
pub mod twofa;
pub mod verification;

use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::vault::Vault;
use registry::Feature;

/// Settings that are a flat `cas <vault> settings <name> enable|disable`,
/// no category needed.
pub const FLAT_FEATURES: &[Feature] = &[encryption::FEATURE, twofa::FEATURE];

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let head = extra.first().map(String::as_str).unwrap_or("");

    match head {
        "" => die!("usage: cas <vault> settings <encryption|2fa|security|verification|backup> ..."),
        "security" => {
            let feature = extra.get(1).map(String::as_str).unwrap_or("");
            if feature == "bruteforceLockout" {
                return security::bruteforce_lockout::dispatch(ctx, vault, &extra[2..], pw);
            }
            if feature == "fileIntegrity" {
                return security::file_integrity::dispatch(ctx, vault, &extra[2..], pw);
            }
            if extra.get(2).map(String::as_str) == Some("state") {
                return registry::state(security::FEATURES, feature, ctx, vault);
            }
            let enable = parse_verb(extra.get(2))?;
            registry::dispatch(security::FEATURES, feature, enable, ctx, vault, pw)
        }
        "verification" => {
            // `settings verification state` (all gated features) vs.
            // `settings verification <feature> state` (just one) vs.
            // `settings verification <feature> enable|disable`.
            if extra.get(1).map(String::as_str) == Some("state") {
                return verification::state(ctx, vault, None);
            }
            let feature = extra.get(1).map(String::as_str).unwrap_or("");
            if extra.get(2).map(String::as_str) == Some("state") {
                return verification::state(ctx, vault, Some(feature));
            }
            let enable = parse_verb(extra.get(2))?;
            verification::dispatch(ctx, vault, feature, enable, pw)
        }
        "backup" => {
            if extra.get(1).map(String::as_str) != Some("auto") {
                die!("usage: cas <vault> settings backup auto enable|disable|keep <N>|state");
            }
            backup_auto::dispatch(ctx, vault, &extra[2..], pw)
        }
        flat => {
            if extra.get(1).map(String::as_str) == Some("state") {
                return registry::state(FLAT_FEATURES, flat, ctx, vault);
            }
            let enable = parse_verb(extra.get(1))?;
            registry::dispatch(FLAT_FEATURES, flat, enable, ctx, vault, pw)
        }
    }
}

fn parse_verb(verb: Option<&String>) -> Result<bool> {
    match verb.map(String::as_str) {
        Some("enable") => Ok(true),
        Some("disable") => Ok(false),
        _ => die!("usage: ... enable|disable|state"),
    }
}
