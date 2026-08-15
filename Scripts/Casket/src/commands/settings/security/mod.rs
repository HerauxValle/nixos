// &desc: "Registry for `cas <vault> settings security <feature> enable|disable` -- one file per security feature under this module, listed here."
pub mod bruteforce_lockout;
pub mod file_integrity;
pub mod ransomware_protection;
pub mod sandbox;
pub mod zeroize;

use crate::commands::settings::registry::Feature;

/// `fileIntegrity`'s `get` here is display-only for `info`'s rollup —
/// its `set` is never reached, since settings/mod.rs routes
/// "fileIntegrity" to `file_integrity::dispatch` before it would hit
/// `registry::dispatch` (same pattern as `bruteforceLockout`).
const FILE_INTEGRITY_DISPLAY: Feature =
    Feature { name: "fileIntegrity", set: |_, _, _, _| unreachable!("routed directly, see settings/mod.rs"), get: file_integrity::is_enabled };

/// Same display-only pattern as `fileIntegrity` — `sandbox`'s `set` is
/// never reached through this table either (settings/mod.rs routes it
/// to `sandbox::dispatch` directly, since it needs a richer verb set
/// than plain enable/disable).
const SANDBOX_DISPLAY: Feature =
    Feature { name: "sandbox", set: |_, _, _, _| unreachable!("routed directly, see settings/mod.rs"), get: sandbox::is_enabled };

pub const FEATURES: &[Feature] =
    &[ransomware_protection::FEATURE, zeroize::FEATURE, bruteforce_lockout::FEATURE, FILE_INTEGRITY_DISPLAY, SANDBOX_DISPLAY];
