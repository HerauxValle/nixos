// &desc: "`rootfs add <name> --preset <distro> [<version>] | --tarball <path>` -- creates a named rootfs environment either via live fetch+checksum+extract (--preset) or extracting a local archive already validated with 'tar -tf' first (--tarball). The actual fetch/extract logic (fetch_preset_into/extract_tarball_into) is reused by update.rs, which replaces just base/ without touching upper/ or re-creating the environment."
use std::fs;
use std::io::Read;
use std::path::Path;

use sha2::{Digest, Sha256};

use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::rootfs::{ensure_dir, validate_name, RESERVED_NAMES};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::proc;
use crate::registry;
use crate::udisks;
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let Some(name) = extra.first() else {
        die!("usage: cas <vault> settings security sandbox rootfs add <name> --preset <distro> [<version>]");
    };
    if RESERVED_NAMES.contains(&name.as_str()) {
        die!("'{name}' is a reserved name -- an environment can't be called that");
    }
    validate_name(name)?;
    gate_inner(ctx, vault, "sandbox", pw)?;

    let env_dir = ensure_dir(vault)?.join(name);
    if env_dir.exists() {
        die!("rootfs environment '{name}' already exists -- 'rootfs remove {name}' first if you want to redo it");
    }
    let base_dir = env_dir.join("base");
    let upper_dir = env_dir.join("upper");

    if extra.iter().any(|s| s == "--preset") && extra.iter().any(|s| s == "--tarball") {
        die!("--preset and --tarball can't be used together");
    }

    match extra.get(1).map(String::as_str) {
        Some("--preset") => {
            let Some(distro) = extra.get(2) else {
                die!("usage: cas <vault> settings security sandbox rootfs add <name> --preset <distro> [<version>]");
            };
            let version = extra.get(3).cloned();
            fs::create_dir_all(&base_dir)?;
            fs::create_dir_all(&upper_dir)?;
            let result = fetch_preset_into(ctx, &base_dir, distro, version.as_deref());
            finish(ctx, &env_dir, name, result, |v| format!(r#"{{"kind":"preset","preset":"{distro}","version":"{v}"}}"#))
        }
        Some("--tarball") => {
            let Some(path) = extra.get(2) else {
                die!("usage: cas <vault> settings security sandbox rootfs add <name> --tarball <path>");
            };
            fs::create_dir_all(&base_dir)?;
            fs::create_dir_all(&upper_dir)?;
            let result = extract_tarball_into(&base_dir, Path::new(path)).map(|()| path.clone());
            finish(ctx, &env_dir, name, result, |_| r#"{"kind":"tarball"}"#.to_string())
        }
        _ => die!("usage: cas <vault> settings security sandbox rootfs add <name> --preset <distro> [<version>] | --tarball <path>"),
    }
}

/// Common cleanup-on-failure + chown + `.casket-source` write + success
/// message shared by both add paths. `label` is the resolved version
/// (preset) or the tarball path (tarball) -- whatever `finish` should
/// report and hand to `source_json`.
fn finish(ctx: &Ctx, env_dir: &Path, name: &str, result: Result<String>, source_json: impl FnOnce(&str) -> String) -> Result<()> {
    let label = match result {
        Ok(label) => label,
        Err(e) => {
            let _ = fs::remove_dir_all(env_dir);
            return Err(e);
        }
    };

    let (uid, gid) = udisks::real_user_ids();
    proc::run("chown", &["-R", &format!("{uid}:{gid}"), &env_dir.to_string_lossy()])?;
    fs::write(env_dir.join(".casket-source"), source_json(&label))?;

    logf!(ctx, "[✓] rootfs environment '{name}' created ({label})");
    Ok(())
}

/// Validates `tarball` (`tar -tf` for a well-formed archive, then
/// `tar -tvf` symlink-target containment -- see `check_symlink_targets`)
/// before touching the filesystem, and extracts it into `base_dir`.
/// Used by both `add --tarball` (fresh `base_dir`) and `update
/// --tarball` (`base_dir` wiped first by the caller).
pub fn extract_tarball_into(base_dir: &Path, tarball: &Path) -> Result<()> {
    if !tarball.is_file() {
        die!("'{}' isn't a file", tarball.display());
    }
    let check = proc::capture("tar", &["-tf", &tarball.to_string_lossy()]);
    if !check.status.success() {
        die!("'{}' doesn't look like a valid tar archive", tarball.display());
    }
    check_symlink_targets(tarball)?;
    proc::run("tar", &["-xf", &tarball.to_string_lossy(), "-C", &base_dir.to_string_lossy()])
}

/// Rejects any symlink member whose target would land outside the
/// archive's own extraction root -- an absolute target (`-> /anything`)
/// outright, or a relative target that `..`s its way past the root
/// once resolved lexically against the symlink's own location. Real
/// distro rootfs tarballs use *in-bounds* relative symlinks
/// structurally (Alpine/Debian's `/bin -> usr/bin`, `/lib -> usr/lib`),
/// so those still pass -- only ones that actually escape are refused.
/// Resolved lexically (no filesystem access): the targets don't exist
/// yet at validation time, since nothing has been extracted.
fn check_symlink_targets(tarball: &Path) -> Result<()> {
    let out = proc::capture("tar", &["-tvf", &tarball.to_string_lossy()]);
    if !out.status.success() {
        die!("'{}': couldn't list archive contents to check symlink targets", tarball.display());
    }
    let listing = String::from_utf8_lossy(&out.stdout);
    for line in listing.lines() {
        if !line.starts_with('l') {
            continue; // not a symlink member
        }
        let Some((member, target)) = line.split_once(" -> ") else {
            continue;
        };
        // The member's own path is the last whitespace-separated field
        // before " -> " in `tar -tvf`'s fixed layout (perms, owner,
        // size, date, time, name).
        let Some(member_path) = member.rsplit(char::is_whitespace).next() else {
            continue;
        };
        if target.starts_with('/') {
            die!("'{}': symlink member '{member_path}' points at an absolute path ('{target}') -- refusing to extract, this can't be verified as staying inside the environment", tarball.display());
        }
        if escapes_root(member_path, target) {
            die!("'{}': symlink member '{member_path}' -> '{target}' resolves outside the archive's own root -- refusing to extract", tarball.display());
        }
    }
    Ok(())
}

/// Lexically resolves `target` relative to `member`'s own parent
/// directory (matching how the kernel would resolve the symlink once
/// extracted), then checks whether that resolution ever goes negative
/// -- i.e. more `..` components than directories consumed so far,
/// meaning it escapes the root the member itself lives under.
fn escapes_root(member: &str, target: &str) -> bool {
    let mut stack: Vec<&str> = member.trim_end_matches('/').split('/').collect();
    stack.pop(); // drop the symlink's own filename -- resolution starts from its parent dir
    for part in target.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if stack.pop().is_none() {
                    return true;
                }
            }
            other => stack.push(other),
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::escapes_root;

    #[test]
    fn in_bounds_relative_symlinks_are_fine() {
        // Alpine/Debian's real-world `/bin -> usr/bin` shape.
        assert!(!escapes_root("bin", "usr/bin"));
        assert!(!escapes_root("usr/sbin", "../bin/busybox"));
    }

    #[test]
    fn escaping_relative_symlinks_are_caught() {
        assert!(escapes_root("escape_link", "../../../tmp"));
        assert!(escapes_root("bin", "../../etc/passwd"));
        // One `..` more than the member's own depth allows -- still
        // escapes, since resolution starts from the member's *parent*
        // directory, not the member itself.
        assert!(escapes_root("bin", "../.."));
    }

    #[test]
    fn nested_member_with_enough_depth_can_go_up_without_escaping() {
        assert!(!escapes_root("a/b/c/link", "../../x"));
    }
}

/// Resolves what to actually download: an explicit version always uses
/// `pinned_url` (+ a fetched `checksum_suffix`, if the distro has one);
/// no version tries `latest_index_url` first (a machine-readable index
/// that carries its own checksum, e.g. Alpine's -- no separate checksum
/// fetch needed), then a plain `latest_url` alias, and refuses if the
/// distro has neither rather than guessing at a URL nobody's verified.
struct Resolved {
    url: String,
    version_label: String,
    expected_sha256: Option<String>,
}

fn resolve(entry: &registry::rootfs::Entry, distro: &str, version: Option<&str>) -> Result<Resolved> {
    let arch = registry::rootfs::resolved_arch(entry);

    if let Some(v) = version {
        let url = registry::rootfs::resolve_pinned_url(entry, &arch, v);
        return Ok(Resolved { url, version_label: v.to_string(), expected_sha256: None });
    }

    if let Some(index_url) = registry::rootfs::resolve_latest_index_url(entry, &arch) {
        let Some(flavor) = &entry.latest_index_flavor else {
            die!("'{distro}' has a latest_index_url but no latest_index_flavor -- registry entry is incomplete");
        };
        let index_body = fetch_text(&index_url)?;
        let release = registry::rootfs::parse_latest_index(&index_body, flavor, &arch)?;
        let dir = index_url.rsplit_once('/').map(|(d, _)| d).unwrap_or(&index_url);
        let url = format!("{dir}/{}", release.file);
        return Ok(Resolved { url, version_label: release.version, expected_sha256: Some(release.sha256) });
    }

    if let Some(url) = registry::rootfs::resolve_latest_url(entry, &arch) {
        return Ok(Resolved { url, version_label: "latest".to_string(), expected_sha256: None });
    }

    die!("'latest' isn't available for '{distro}' yet -- specify a version explicitly: rootfs add <name> --preset {distro} <version>");
}

/// Fetches, checksum-verifies, and extracts a preset tarball into
/// `base_dir`. Returns the resolved version label on success. Used by
/// both `add --preset` (fresh `base_dir`) and `update` (`base_dir`
/// wiped first by the caller) -- never touches `upper_dir` or writes
/// `.casket-source` itself, that's the caller's job.
pub fn fetch_preset_into(ctx: &Ctx, base_dir: &Path, distro: &str, version: Option<&str>) -> Result<String> {
    let entry = registry::rootfs::entry(distro)?;
    let resolved = resolve(&entry, distro, version)?;

    logf!(ctx, "[cas] fetching {} ...", resolved.url);
    let bytes = fetch(&resolved.url)?;

    let expected = match resolved.expected_sha256 {
        Some(sha) => Some(sha),
        None => match registry::rootfs::checksum_url(&entry, &resolved.url) {
            Some(checksum_url) => {
                logf!(ctx, "[i] verifying against {checksum_url}");
                Some(expected_hash(&fetch_text(&checksum_url)?, &resolved.url)?)
            }
            None => None,
        },
    };

    match expected {
        Some(expected) => {
            let actual = hex_sha256(&bytes);
            if !actual.eq_ignore_ascii_case(&expected) {
                die!("checksum mismatch for {}\n    expected: {expected}\n    got:      {actual}\n    download rejected, nothing was written", resolved.url);
            }
            logf!(ctx, "[✓] checksum verified");
        }
        None => logf!(ctx, "  [!] no official checksum available for '{distro}' -- downloaded tarball is unverified"),
    }

    let tmp_tarball = base_dir.join("..").join(".download.tmp");
    fs::write(&tmp_tarball, &bytes)?;
    let extract_result = proc::run("tar", &["-xf", &tmp_tarball.to_string_lossy(), "-C", &base_dir.to_string_lossy()]);
    let _ = fs::remove_file(&tmp_tarball);
    extract_result?;

    Ok(resolved.version_label)
}

fn fetch(url: &str) -> Result<Vec<u8>> {
    let response = ureq::get(url).call().map_err(|e| crate::error::CasError::new(format!("fetch failed: {url}: {e}")))?;
    let mut bytes = Vec::new();
    response.into_reader().read_to_end(&mut bytes)?;
    Ok(bytes)
}

fn fetch_text(url: &str) -> Result<String> {
    let response = ureq::get(url).call().map_err(|e| crate::error::CasError::new(format!("fetch failed: {url}: {e}")))?;
    response.into_string().map_err(|e| crate::error::CasError::new(format!("fetch failed: {url}: {e}")))
}

fn hex_sha256(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Parses a checksum file that's either a single `<hash>  <filename>`
/// line (Alpine/Debian's per-artifact `.sha256`) or a multi-line
/// manifest (Ubuntu's `SHA256SUMS`, one line per file in the release,
/// filenames prefixed `*`) -- finds the line whose filename matches the
/// tarball URL's basename, or falls back to the only line if there's
/// just one.
fn expected_hash(checksum_body: &str, tarball_url: &str) -> Result<String> {
    let basename = tarball_url.rsplit('/').next().unwrap_or(tarball_url);
    let lines: Vec<&str> = checksum_body.lines().filter(|l| !l.trim().is_empty()).collect();
    if lines.len() == 1 {
        if let Some(hash) = lines[0].split_whitespace().next() {
            return Ok(hash.to_string());
        }
    }
    for line in &lines {
        let mut parts = line.split_whitespace();
        let (Some(hash), Some(file)) = (parts.next(), parts.next()) else { continue };
        if file.trim_start_matches('*').ends_with(basename) {
            return Ok(hash.to_string());
        }
    }
    die!("could not find a checksum for '{basename}' in the fetched checksum file");
}
