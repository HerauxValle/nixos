// &desc: "v4 -> v5: no meta-JSON shape change to existing fields, but `tamper::Protected` now covers the three new header_room/header_offset/header_encryption fields (see header/relocate.rs) -- an existing `meta_hmac` was computed against the old, narrower field set, so it can never match again post-upgrade regardless of whether anything was actually tampered with. Same 'fall back to Unprotected, not a false Tampered' fix as v3/v4's identical shape-change problem."
use serde_json::{Map, Value};

use super::Step;

pub const STEP: Step = Step {
    version: 5,
    meta: Some(migrate_meta),
    layout: None,
};

fn migrate_meta(map: &mut Map<String, Value>) {
    map.remove("meta_hmac");
}
