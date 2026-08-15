// &desc: "Parses data/rootfs-presets.toml and resolves {arch}/{version}/{minor} placeholders into concrete URLs. Offline/pure -- no network here; see commands::settings::security::sandbox::rootfs::add for the fetch+checksum step that actually uses these URLs."
use std::collections::BTreeMap;

use serde::Deserialize;

use crate::die;
use crate::error::Result;

const DATA: &str = include_str!("data/rootfs-presets.toml");

#[derive(Deserialize)]
pub struct Entry {
    pub latest_url: String,
    pub pinned_url: String,
    pub checksum_suffix: Option<String>,
}

pub fn load() -> BTreeMap<String, Entry> {
    toml::from_str(DATA).expect("data/rootfs-presets.toml is malformed -- this is a build-time asset, not user input")
}

pub fn entry(distro: &str) -> Result<Entry> {
    let mut table = load();
    match table.remove(distro) {
        Some(e) => Ok(e),
        None => die!("unknown rootfs preset '{distro}' -- known presets: {}", table.into_keys().collect::<Vec<_>>().join(", ")),
    }
}

/// The architecture string used in registry URL templates -- matches
/// `std::env::consts::ARCH` for every architecture this registry
/// actually lists entries for (x86_64/aarch64), so no translation table
/// is needed today. If a distro's naming ever diverges, that's the
/// escape hatch this comment is flagging for later, not a defect now.
pub fn host_arch() -> &'static str {
    std::env::consts::ARCH
}

/// First two dot-separated components of a version string --
/// `"3.20.3"` -> `"3.20"`. Only meaningful for `pinned_url` templates
/// that need a shorter release-series path segment (Alpine's
/// `v{minor}/releases/...`).
fn minor(version: &str) -> String {
    version.splitn(3, '.').take(2).collect::<Vec<_>>().join(".")
}

fn substitute(template: &str, arch: &str, version: Option<&str>) -> String {
    let mut out = template.replace("{arch}", arch);
    if let Some(v) = version {
        out = out.replace("{version}", v).replace("{minor}", &minor(v));
    }
    out
}

pub fn resolve_latest_url(entry: &Entry, arch: &str) -> String {
    substitute(&entry.latest_url, arch, None)
}

pub fn resolve_pinned_url(entry: &Entry, arch: &str, version: &str) -> String {
    substitute(&entry.pinned_url, arch, Some(version))
}

pub fn checksum_url(entry: &Entry, resolved_tarball_url: &str) -> Option<String> {
    entry.checksum_suffix.as_ref().map(|suffix| format!("{resolved_tarball_url}{suffix}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Structural check applied to *every* entry the registry actually
    /// has -- adding a new distro to the TOML file gets this coverage
    /// for free, no new test function needed. Catches the real failure
    /// mode (a leftover `{placeholder}` from a typo'd template) without
    /// hand-copying an expected URL string per distro.
    #[test]
    fn every_entry_resolves_cleanly() {
        for (name, e) in load() {
            let latest = resolve_latest_url(&e, "x86_64");
            assert!(!latest.contains('{'), "{name}: latest_url left an unsubstituted placeholder: {latest}");
            assert!(latest.contains("x86_64"), "{name}: latest_url doesn't contain the resolved arch: {latest}");

            let pinned = resolve_pinned_url(&e, "x86_64", "1.2.3");
            assert!(!pinned.contains('{'), "{name}: pinned_url left an unsubstituted placeholder: {pinned}");
            assert!(pinned.contains("1.2.3"), "{name}: pinned_url doesn't contain the resolved version: {pinned}");

            if let Some(url) = checksum_url(&e, &latest) {
                assert!(url.starts_with(&latest), "{name}: checksum_url should extend the resolved tarball url: {url}");
            }
        }
    }

    /// One concrete spot-check (not one per distro) so a template typo
    /// that happens to still satisfy the structural check above (e.g.
    /// swapped path segments) has at least one exact-match tripwire.
    #[test]
    fn alpine_spot_check() {
        let e = entry("alpine").unwrap();
        assert_eq!(resolve_latest_url(&e, "x86_64"), "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-latest-x86_64.tar.gz");
        assert_eq!(
            resolve_pinned_url(&e, "x86_64", "3.20.3"),
            "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-minirootfs-3.20.3-x86_64.tar.gz"
        );
    }

    #[test]
    fn unknown_preset_lists_known_names() {
        let names: Vec<String> = load().into_keys().collect();
        let err = entry("not-a-real-distro").map(|_| ()).unwrap_err().to_string();
        for name in names {
            assert!(err.contains(&name), "error should list known preset '{name}': {err}");
        }
    }

    #[test]
    fn minor_handles_two_and_three_component_versions() {
        assert_eq!(minor("3.20.3"), "3.20");
        assert_eq!(minor("24.04"), "24.04");
    }
}
