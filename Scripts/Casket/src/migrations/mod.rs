// &desc: "Migration registry: one file per schema version, each holding whatever that version actually changed -- a meta-JSON transform, an in-vault layout transform, or both, as a single Step. Each Step declares its own target `version`, which is the sole source of truth for ordering -- file naming and array position are cosmetic only. `meta` runs whenever the trailer is read (vault may be closed); `layout` runs once a vault is mounted, since it touches real files."
use serde_json::{Map, Value};

use crate::ctx::Ctx;
use crate::vault::Vault;

mod v1;
mod v2;
mod v3;
mod v4;
mod v5;
mod v6;
mod v7;

pub mod image_rebuild;

pub struct Step {
    /// The schema version this step produces. A vault at version N-1
    /// needs this step; a vault already at N or later doesn't. This is
    /// what orders migrations — not where the file lives or where its
    /// entry sits in STEPS below.
    pub version: u64,
    pub meta: Option<fn(&mut Map<String, Value>)>,
    pub layout: Option<fn(&Ctx, &Vault)>,
    /// True when reaching this version can't be done in place -- the
    /// existing `vault.img` structurally can't become the new shape (e.g.
    /// a bigger fixed LUKS2 data offset baked in at `luksFormat` time),
    /// so the only way to apply this step is `image_rebuild::rebuild`:
    /// format a brand-new image with the new params, copy every real
    /// file across, verify, atomically swap it in at the same path.
    /// Defaults to `false` for every step that only needs a meta/layout
    /// transform on the existing image -- set this explicitly, don't
    /// leave it implicit, since it changes `open`'s behavior (a confirm
    /// prompt + real disk work before the vault becomes usable, not just
    /// mounting).
    pub requires_new_image: bool,
}

/// To add a migration: create a file exposing `pub const STEP: Step`
/// with a `version` one higher than the current max in this list, add
/// it below, and bump `version::CURRENT` to match. Leave whichever half
/// of `Step` a version didn't touch as `None`. Entries don't need to be
/// listed in order — `applicable_steps` sorts by `version` itself.
const STEPS: &[Step] = &[v1::STEP, v2::STEP, v3::STEP, v4::STEP, v5::STEP, v6::STEP, v7::STEP];

/// Every step needed to reach `version::CURRENT` from `from`, ascending.
fn applicable_steps(from: u64) -> Vec<&'static Step> {
    let mut steps: Vec<&Step> = STEPS.iter().filter(|s| s.version > from).collect();
    steps.sort_by_key(|s| s.version);
    steps
}

/// Whether any step between `from` and `version::CURRENT` needs a full
/// image rebuild -- checked generically by version number so this never
/// needs updating when a *future* version adds another
/// `requires_new_image` step; it just works. Used by `open.rs` to decide
/// whether to prompt before mounting, without ever naming a specific
/// schema version in that call site (deliberate: also covers a
/// downgraded `cas` binary being pointed at a vault created/migrated by
/// a newer build with a still-higher `version::CURRENT` than this
/// binary knows about landing on a version that happens to be at or
/// below what this binary's own STEPS table considers image-rebuilding).
pub fn requires_new_image(from: u64) -> bool {
    applicable_steps(from).iter().any(|s| s.requires_new_image)
}

/// Apply every meta-JSON transform between `from` and current.
pub fn migrate_meta(mut value: Value, from: u64) -> Value {
    let Value::Object(ref mut map) = value else {
        return value;
    };
    for step in applicable_steps(from) {
        if let Some(f) = step.meta {
            f(map);
        }
    }
    value
}

/// Apply every in-vault layout transform between `from` and current.
/// Called once a vault is mounted; each step must be safe to re-run on
/// an already-migrated vault (guard on "old path exists, new one
/// doesn't"), since `from` reflects the meta trailer's version, not a
/// separate on-disk marker.
pub fn migrate_layout(ctx: &Ctx, vault: &Vault, from: u64) {
    for step in applicable_steps(from) {
        if let Some(f) = step.layout {
            f(ctx, vault);
        }
    }
}
