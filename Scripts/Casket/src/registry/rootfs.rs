// &desc: "Parses data/rootfs-presets.toml and resolves {arch}/{version}/{minor} placeholders into concrete URLs, plus Alpine's YAML release-index format. Offline/pure -- see commands::settings::security::sandbox::rootfs::add for the fetch+checksum step that actually uses these."
use std::collections::BTreeMap;

use serde::Deserialize;

use crate::die;
use crate::error::Result;

const DATA: &str = include_str!("data/rootfs-presets.toml");

#[derive(Deserialize)]
pub struct Entry {
    /// Machine-readable index (currently Alpine's `latest-releases.yaml`
    /// shape only -- see `resolve_latest_via_index`) carrying its own
    /// checksum. If present, this is how "latest" resolves; if absent
    /// and `latest_url` is too, "latest" isn't available for this
    /// distro and `add --preset <distro>` with no version refuses.
    pub latest_index_url: Option<String>,
    /// Which `flavor:` field to match within the index (Alpine's index
    /// lists several artifacts per release; only one is a minirootfs).
    pub latest_index_flavor: Option<String>,
    /// A directly-downloadable "always current" URL, for a distro whose
    /// alias scheme doesn't need index parsing. No current registry
    /// entry uses this -- kept as a real alternative, not dead code.
    pub latest_url: Option<String>,
    pub pinned_url: String,
    pub checksum_suffix: Option<String>,
    /// Per-host-arch override when a distro's own arch naming doesn't
    /// match `std::env::consts::ARCH` (e.g. Ubuntu/Debian call x86_64
    /// "amd64"). Absent host arches fall back to the unmodified name.
    pub arch_names: Option<BTreeMap<String, String>>,
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

/// The architecture string used in registry URL templates -- Rust's own
/// arch name, unless `entry.arch_names` overrides it for this distro.
pub fn host_arch() -> &'static str {
    std::env::consts::ARCH
}

pub fn resolved_arch(entry: &Entry) -> String {
    let host = host_arch();
    entry.arch_names.as_ref().and_then(|m| m.get(host)).cloned().unwrap_or_else(|| host.to_string())
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

pub fn resolve_pinned_url(entry: &Entry, arch: &str, version: &str) -> String {
    substitute(&entry.pinned_url, arch, Some(version))
}

pub fn resolve_latest_url(entry: &Entry, arch: &str) -> Option<String> {
    entry.latest_url.as_ref().map(|t| substitute(t, arch, None))
}

pub fn resolve_latest_index_url(entry: &Entry, arch: &str) -> Option<String> {
    entry.latest_index_url.as_ref().map(|t| substitute(t, arch, None))
}

pub fn checksum_url(entry: &Entry, resolved_tarball_url: &str) -> Option<String> {
    entry.checksum_suffix.as_ref().map(|suffix| {
        if let Some(dir) = resolved_tarball_url.rsplit_once('/') {
            format!("{}{suffix}", dir.0)
        } else {
            format!("{resolved_tarball_url}{suffix}")
        }
    })
}

/// One release entry parsed out of an Alpine-shaped `latest-releases.
/// yaml` index: a flat sequence of `-`-prefixed blocks, each a set of
/// `key: value` lines. Hand-parsed rather than pulling in a YAML crate
/// for one document shape this simple -- see `parse_latest_index`.
pub struct IndexRelease {
    pub file: String,
    pub version: String,
    pub sha256: String,
}

/// Finds the release block whose `flavor:` matches `flavor` and whose
/// `arch:` matches `arch` -- the first one wins if more than one
/// somehow matches (the index lists one flavor/arch pair once in
/// practice).
pub fn parse_latest_index(yaml: &str, flavor: &str, arch: &str) -> Result<IndexRelease> {
    let mut blocks: Vec<BTreeMap<&str, &str>> = Vec::new();
    let mut current: BTreeMap<&str, &str> = BTreeMap::new();
    for line in yaml.lines() {
        let trimmed = line.trim();
        if trimmed == "-" {
            if !current.is_empty() {
                blocks.push(std::mem::take(&mut current));
            }
            continue;
        }
        if let Some((key, value)) = trimmed.split_once(':') {
            current.insert(key.trim(), value.trim().trim_matches('"'));
        }
    }
    if !current.is_empty() {
        blocks.push(current);
    }

    for block in blocks {
        if block.get("flavor") == Some(&flavor) && block.get("arch") == Some(&arch) {
            let (Some(file), Some(version), Some(sha256)) = (block.get("file"), block.get("version"), block.get("sha256")) else {
                die!("release index entry for {flavor}/{arch} is missing file/version/sha256");
            };
            return Ok(IndexRelease { file: file.to_string(), version: version.to_string(), sha256: sha256.to_string() });
        }
    }
    die!("no release found for flavor '{flavor}' arch '{arch}' in the fetched index");
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
            let arch = resolved_arch(&e);
            let pinned = resolve_pinned_url(&e, &arch, "1.2.3");
            assert!(!pinned.contains('{'), "{name}: pinned_url left an unsubstituted placeholder: {pinned}");
            assert!(pinned.contains("1.2.3"), "{name}: pinned_url doesn't contain the resolved version: {pinned}");

            if let Some(url) = checksum_url(&e, &pinned) {
                assert!(!url.contains('{'), "{name}: checksum_suffix left an unsubstituted placeholder: {url}");
            }
            if let Some(latest) = resolve_latest_url(&e, &arch) {
                assert!(!latest.contains('{'), "{name}: latest_url left an unsubstituted placeholder: {latest}");
            }
            if let Some(index) = resolve_latest_index_url(&e, &arch) {
                assert!(!index.contains('{'), "{name}: latest_index_url left an unsubstituted placeholder: {index}");
            }
        }
    }

    #[test]
    fn alpine_spot_check() {
        let e = entry("alpine").unwrap();
        assert_eq!(
            resolve_pinned_url(&e, "x86_64", "3.20.3"),
            "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-minirootfs-3.20.3-x86_64.tar.gz"
        );
        assert_eq!(resolve_latest_index_url(&e, "x86_64").unwrap(), "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml");
    }

    #[test]
    fn ubuntu_arch_name_override() {
        let e = entry("ubuntu").unwrap();
        assert_eq!(resolved_arch(&e), if host_arch() == "x86_64" { "amd64" } else if host_arch() == "aarch64" { "arm64" } else { host_arch() });
        assert!(resolve_latest_url(&e, "amd64").is_none(), "ubuntu shouldn't have a direct latest_url -- no verified alias exists");
        assert!(resolve_latest_index_url(&e, "amd64").is_none());
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

    #[test]
    fn parses_alpine_style_index() {
        let yaml = r#"---
-
  title: "Mini root filesystem"
  branch: v3.24
  arch: x86_64
  version: 3.24.1
  flavor: alpine-minirootfs
  file: alpine-minirootfs-3.24.1-x86_64.tar.gz
  sha256: deadbeef
-
  title: "Netboot"
  arch: x86_64
  flavor: netboot
  file: netboot-thing.tar.gz
"#;
        let r = parse_latest_index(yaml, "alpine-minirootfs", "x86_64").unwrap();
        assert_eq!(r.file, "alpine-minirootfs-3.24.1-x86_64.tar.gz");
        assert_eq!(r.version, "3.24.1");
        assert_eq!(r.sha256, "deadbeef");
    }
}
