// &desc: "v0 -> v1: no meta-JSON shape change; flat .cas-snapshots/ becomes .casket/snapshots/, namespaced under the .casket/ root that ransomwareProtection locks as a whole. Moves existing snapshots across instead of orphaning them under the old path."
use crate::ctx::Ctx;
use crate::logf;
use crate::vault::Vault;

use super::Step;

pub const STEP: Step = Step {
    version: 1,
    meta: None,
    layout: Some(migrate_layout),
    requires_new_image: false,
};

const OLD_SNAP_DIR: &str = ".cas-snapshots";

fn migrate_layout(ctx: &Ctx, vault: &Vault) {
    let old = vault.mnt.join(OLD_SNAP_DIR);
    if !old.exists() {
        return;
    }
    let new = vault.casket_dir().join("snapshots");
    if new.exists() {
        return; // already migrated (or a fresh .casket/snapshots/ exists independently)
    }
    if let Err(e) = std::fs::create_dir_all(vault.casket_dir()) {
        logf!(ctx, "  [!] could not migrate {OLD_SNAP_DIR}/ -> .casket/snapshots/: {e}");
        return;
    }
    match std::fs::rename(&old, &new) {
        Ok(()) => logf!(ctx, "  [i] migrated {OLD_SNAP_DIR}/ -> .casket/snapshots/"),
        Err(e) => logf!(ctx, "  [!] could not migrate {OLD_SNAP_DIR}/ -> .casket/snapshots/: {e}"),
    }
}
