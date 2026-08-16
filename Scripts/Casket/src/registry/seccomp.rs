// &desc: "Parses data/seccomp-presets.toml -- 4 built-in presets (default/strict/compute/none), syscalls listed by name only. Named custom profiles (`seccomp set custom:<name>`) are deliberately not in this file -- they're vault-wide user data managed under `.seccomp.d/`, not a build-time registry entry, see commands::settings::security::sandbox::seccomp::profiles."
use std::collections::BTreeMap;

use serde::Deserialize;

const DATA: &str = include_str!("data/seccomp-presets.toml");

/// Every built-in preset name valid for `seccomp set <preset>` -- a
/// named custom profile is referenced separately, as `custom:<name>`,
/// not by a bare name from this list (see `commands::settings::
/// security::sandbox::seccomp::set`, which checks both).
pub const PRESET_NAMES: &[&str] = &["default", "strict", "compute", "none"];

#[derive(Deserialize)]
struct RawEntry {
    mode: String,
    #[serde(default)]
    syscalls: Vec<String>,
    #[serde(default)]
    syscalls_from: Option<String>,
    #[serde(default)]
    deny_syscalls: Vec<String>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    /// `syscalls` are blocked; everything else is allowed.
    Denylist,
    /// Only `syscalls` are allowed; everything else is blocked.
    Allowlist,
    /// No filter at all.
    AllowAll,
}

pub struct Entry {
    pub mode: Mode,
    pub syscalls: Vec<String>,
}

/// Parses the registry and resolves `syscalls_from`/`deny_syscalls`
/// (currently just `compute`, derived from `strict` minus networking)
/// into a concrete syscall list per entry -- callers never see the
/// "derive from another preset" indirection.
pub fn load() -> BTreeMap<String, Entry> {
    let raw: BTreeMap<String, RawEntry> = toml::from_str(DATA).expect("data/seccomp-presets.toml is malformed -- this is a build-time asset, not user input");

    raw.iter()
        .map(|(name, r)| {
            let mut syscalls = match &r.syscalls_from {
                Some(from) => raw.get(from).map(|base| base.syscalls.clone()).unwrap_or_default(),
                None => r.syscalls.clone(),
            };
            syscalls.retain(|s| !r.deny_syscalls.contains(s));
            let mode = match r.mode.as_str() {
                "denylist" => Mode::Denylist,
                "allowlist" => Mode::Allowlist,
                "allow_all" => Mode::AllowAll,
                other => panic!("data/seccomp-presets.toml: unknown mode '{other}' in [{name}]"),
            };
            (name.clone(), Entry { mode, syscalls })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_preset_syscall_resolves_on_x86_64() {
        // Every name a shipped preset references must actually exist
        // in the x86_64 syscall table, or the preset would silently
        // under-allow on the most common architecture. aarch64
        // legitimately lacks some legacy names (stat/access/rename/
        // ...), which is fine -- glibc translates those C calls into
        // the *at() syscalls that table does have.
        let x86 = crate::sandbox::syscall_table::x86_64_table();
        for (preset_name, entry) in load() {
            for syscall in &entry.syscalls {
                assert!(x86.contains_key(syscall), "preset '{preset_name}' references unknown syscall '{syscall}'");
            }
        }
    }

    #[test]
    fn every_registry_entry_loads_and_has_a_valid_mode() {
        let presets = load();
        for name in ["default", "strict", "compute", "none"] {
            assert!(presets.contains_key(name), "missing preset '{name}'");
        }
    }

    #[test]
    fn compute_derives_from_strict_minus_networking() {
        let presets = load();
        let strict = &presets["strict"];
        let compute = &presets["compute"];
        assert_eq!(compute.mode, Mode::Allowlist);
        assert!(strict.syscalls.contains(&"socket".to_string()));
        assert!(!compute.syscalls.contains(&"socket".to_string()));
        // Compute should be a strict subset of strict, not a
        // completely different list.
        for s in &compute.syscalls {
            assert!(strict.syscalls.contains(s), "compute has '{s}' that strict doesn't");
        }
    }

    #[test]
    fn none_allows_everything() {
        assert_eq!(load()["none"].mode, Mode::AllowAll);
    }

    #[test]
    fn preset_names_excludes_custom_which_has_no_registry_entry() {
        assert!(!PRESET_NAMES.contains(&"custom"));
        assert!(!load().contains_key("custom"));
    }
}
