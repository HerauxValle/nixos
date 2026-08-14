// &desc: "Registry for `cas <vault> settings security <feature> enable|disable` -- one file per security feature under this module, listed here."
pub mod ransomware_protection;

use crate::commands::settings::registry::Feature;

pub const FEATURES: &[Feature] = &[ransomware_protection::FEATURE];
