// &desc: "v3 -> v4: no meta-JSON shape change to the fields themselves, but `tamper::Protected` now covers `bruteforce_threshold` in addition to `bruteforce_lockout` -- an existing `meta_hmac` was computed against the old, narrower field set, so it can never match again post-upgrade regardless of whether anything was actually tampered with. Unconditionally drops any stored `meta_hmac`, same 'fall back to Unprotected, not a false Tampered' fix as v3's identical seccomp-shape problem -- this one has a wider blast radius (every vault with any existing HMAC baseline, not just ones that used the old custom-seccomp feature), since the Protected struct's shape changed for everyone, not just users of one specific setting."
use serde_json::{Map, Value};

use super::Step;

pub const STEP: Step = Step {
    version: 4,
    meta: Some(migrate_meta),
    layout: None,
};

fn migrate_meta(map: &mut Map<String, Value>) {
    map.remove("meta_hmac");
}
