// &desc: "Registry for `cas <vault> settings security <feature> enable|disable` -- one file per security feature under this module, listed here."
pub mod bruteforce_lockout;
pub mod header_encryption;
pub mod header_offset;
pub mod ransomware_protection;
pub mod sandbox;
pub mod zeroize;

use crate::commands::settings::registry::Feature;

/// Display-only pattern — `sandbox`'s `set` is
/// never reached through this table either (settings/mod.rs routes it
/// to `sandbox::dispatch` directly, since it needs a richer verb set
/// than plain enable/disable).
const SANDBOX_DISPLAY: Feature =
    Feature { name: "sandbox", set: |_, _, _, _| unreachable!("routed directly, see settings/mod.rs"), get: sandbox::is_enabled };

/// Same display-only pattern -- `headerOffset`'s `set` is never reached
/// through this table either (routed to `header_offset::dispatch`
/// directly, since enable needs to conditionally print a
/// headerEncryption notice).
const HEADER_OFFSET_DISPLAY: Feature =
    Feature { name: "headerOffset", set: |_, _, _, _| unreachable!("routed directly, see settings/mod.rs"), get: header_offset::is_enabled };

const HEADER_ENCRYPTION_DISPLAY: Feature =
    Feature { name: "headerEncryption", set: |_, _, _, _| unreachable!("routed directly, see settings/mod.rs"), get: header_encryption::is_enabled };

pub const FEATURES: &[Feature] = &[
    ransomware_protection::FEATURE,
    zeroize::FEATURE,
    bruteforce_lockout::FEATURE,
    SANDBOX_DISPLAY,
    HEADER_OFFSET_DISPLAY,
    HEADER_ENCRYPTION_DISPLAY,
];
