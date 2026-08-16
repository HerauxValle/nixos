// &desc: "v2 -> v3: converts the old one-custom-list-per-target seccomp feature into the named, reusable custom-profile registry (`.seccomp.d/`). Meta step renames each target's bare `\"custom\"` value to `\"custom:<target-key>\"` (the target key becomes the new profile's name) and renames `sandbox_seccomp_custom_hash` -> `sandbox_seccomp_profile_hash`. Layout step converts each old plain-text `.casket-seccomp` file (one syscall per line) into the equivalent TOML profile at its new location, using the same target-key-as-profile-name convention the meta step assumed."
use std::fs;

use serde_json::{Map, Value};

use crate::commands::settings::security::sandbox::seccomp::profiles::Profile;
use crate::ctx::Ctx;
use crate::logf;
use crate::vault::Vault;

use super::Step;

pub const STEP: Step = Step {
    version: 3,
    meta: Some(migrate_meta),
    layout: Some(migrate_layout),
};

fn migrate_meta(map: &mut Map<String, Value>) {
    let mut touched = false;

    if let Some(Value::Object(seccomp)) = map.get_mut("sandbox_seccomp") {
        for (key, value) in seccomp.iter_mut() {
            if value.as_str() == Some("custom") {
                *value = Value::String(format!("custom:{key}"));
                touched = true;
            }
        }
    }
    if let Some(old) = map.remove("sandbox_seccomp_custom_hash") {
        map.insert("sandbox_seccomp_profile_hash".to_string(), old);
        touched = true;
    }

    // The tamper HMAC (`meta_hmac`) is computed over the *current*
    // `tamper::Protected` field shape -- a real vault that legitimately
    // set `sandbox_seccomp`/`sandbox_seccomp_custom_hash` under the old
    // shape has an HMAC that was computed against that old shape's
    // bytes (old field name, old `"custom"` value). Once this migration
    // renames the field and rewrites the value, that stored HMAC can
    // never match again -- not because anything was tampered with, but
    // because the shape changed out from under it. Dropping it here
    // (rather than leaving a permanently-mismatching HMAC in place)
    // means `open`'s tamper check reports "Unprotected" and simply
    // establishes a fresh baseline on the next verified write, instead
    // of "Tampered" -- which would trigger `reset_to_safe` on every
    // single open forever, over a migration, not an actual attack. This
    // is exactly the case `commands::open::check_tamper`'s own doc
    // comment already anticipates ("a migration bug, a hand edit made
    // before this feature existed").
    if touched {
        map.remove("meta_hmac");
    }
}

/// Parses the old plain-text format: one syscall name per line, blank
/// lines and `#`-prefixed comments skipped -- exactly what the old
/// `parse_custom_syscalls`/`edit custom` placeholder produced.
fn parse_old_format(contents: &str) -> Vec<String> {
    contents.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('#')).map(str::to_string).collect()
}

fn migrate_one(ctx: &Ctx, vault: &Vault, old_path: &std::path::Path, profile_name: &str) {
    let new_path = crate::commands::settings::security::sandbox::seccomp::profiles::path(vault, profile_name);
    if new_path.exists() {
        return; // already migrated
    }
    let Ok(contents) = fs::read_to_string(old_path) else {
        return;
    };
    let profile = Profile { default: "deny".to_string(), allow: parse_old_format(&contents), deny: Vec::new() };
    let Some(parent) = new_path.parent() else {
        return;
    };
    if fs::create_dir_all(parent).is_err() {
        logf!(ctx, "  [!] could not create .seccomp.d/ while migrating '{profile_name}'");
        return;
    }
    let Ok(toml_contents) = toml::to_string_pretty(&profile) else {
        return;
    };
    if fs::write(&new_path, toml_contents).is_err() {
        logf!(ctx, "  [!] could not write migrated seccomp profile '{profile_name}'");
        return;
    }
    let _ = fs::remove_file(old_path);
    logf!(ctx, "  [i] migrated custom seccomp list for '{profile_name}' to .seccomp.d/{profile_name}.toml");
}

/// Deliberately doesn't recompute/re-store the profile's hash in
/// `Meta` -- that needs the vault's derived secret (to call
/// `tamper::refresh`), which isn't available from a layout step (see
/// `migrations::mod`'s doc comment: layout steps touch the mounted
/// filesystem only, meta steps touch the trailer only, never both).
/// The renamed `sandbox_seccomp_profile_hash` entry (from the meta
/// step) still holds the *old* file's hash, which won't match the new
/// TOML file's bytes -- so the first `exec` after this migration falls
/// back to `strict` via `resolve_seccomp`'s existing "hash mismatch"
/// path, with its existing warning message, rather than silently
/// trusting unverified migrated data. Safe by construction, matching
/// this codebase's "fail toward more protective" rule elsewhere
/// (`tamper::reset_to_safe`) -- and low-impact in practice, since
/// `exec` itself was broken end-to-end before this same release, so no
/// vault could have been relying on a working custom filter yet.
fn migrate_layout(ctx: &Ctx, vault: &Vault) {
    let root_old = vault.mnt.join(".casket-seccomp");
    if root_old.exists() {
        migrate_one(ctx, vault, &root_old, "_root");
    }

    let rootfs_dir = vault.rootfs_dir();
    let Ok(entries) = fs::read_dir(&rootfs_dir) else {
        return;
    };
    for entry in entries.filter_map(|e| e.ok()) {
        if !entry.file_type().map(|t| t.is_dir()).unwrap_or(false) {
            continue;
        }
        let Some(name) = entry.file_name().into_string().ok() else {
            continue;
        };
        let old = entry.path().join(".casket-seccomp");
        if old.exists() {
            migrate_one(ctx, vault, &old, &name);
        }
    }
}
