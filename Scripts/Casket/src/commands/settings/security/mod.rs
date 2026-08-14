// &desc: "Registry for `cas <vault> settings security <feature> enable|disable` -- one file per security feature under this module, listed here."
pub mod bruteforce_lockout;
pub mod ransomware_protection;
pub mod zeroize;

use crate::commands::settings::registry::Feature;

pub const FEATURES: &[Feature] = &[ransomware_protection::FEATURE, zeroize::FEATURE, bruteforce_lockout::FEATURE];
