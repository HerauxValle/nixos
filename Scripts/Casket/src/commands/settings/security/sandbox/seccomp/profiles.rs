// &desc: "`cas <vault> settings security sandbox seccomp custom list|create|delete|rename|edit` -- named, reusable custom seccomp profiles. Each profile is its own TOML file under `.seccomp.d/` (mode-independent: an `allow` list, a `deny` list, and a `default` action for anything in neither), referenced by any target via the same flat `seccomp set <name>` built-ins use -- no prefix. `create`/`rename` refuse any name colliding with a built-in preset, so the shared namespace never actually clashes. Replaces the older one-per-target-only custom file (see migrations::v3)."
use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::commands::settings::gate::gate_inner;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::name;
use crate::sandbox::seccomp::Filter;
use crate::sandbox::syscall_table;
use crate::tamper;
use crate::vault::Vault;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    /// Fallback action for any syscall named in neither list below.
    /// Defaults to the safer "deny" for a brand-new profile.
    #[serde(default = "default_action")]
    pub default: String,
    #[serde(default)]
    pub allow: Vec<String>,
    #[serde(default)]
    pub deny: Vec<String>,
}

fn default_action() -> String {
    "deny".to_string()
}

impl Default for Profile {
    fn default() -> Self {
        Profile { default: default_action(), allow: Vec::new(), deny: Vec::new() }
    }
}

impl Profile {
    pub fn to_filter(&self) -> Filter {
        Filter { default_deny: self.default != "allow", allow: self.allow.clone(), deny: self.deny.clone() }
    }
}

pub fn dir(vault: &Vault) -> PathBuf {
    vault.seccomp_profiles_dir()
}

pub fn path(vault: &Vault, name: &str) -> PathBuf {
    dir(vault).join(format!("{name}.toml"))
}

pub fn exists(vault: &Vault, name: &str) -> bool {
    path(vault, name).exists()
}

pub fn read(vault: &Vault, name: &str) -> Result<Profile> {
    let contents = fs::read_to_string(path(vault, name))?;
    toml::from_str(&contents).map_err(|e| crate::error::CasError::new(format!("profile '{name}' has invalid TOML: {e}")))
}

fn write(vault: &Vault, name: &str, profile: &Profile) -> Result<String> {
    fs::create_dir_all(dir(vault))?;
    let contents = toml::to_string_pretty(profile).expect("Profile always serializes");
    fs::write(path(vault, name), &contents)?;
    let mut hasher = Sha256::new();
    hasher.update(contents.as_bytes());
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// Persists `profile` to disk, records its hash in `Meta`, and refreshes
/// the tamper HMAC if verification ran -- the one place every mutating
/// profile command (`create`, `default`, `add`, `remove`, the raw
/// `edit`) converges through, so none of them can forget a step the
/// others do.
fn save(ctx: &Ctx, vault: &Vault, name: &str, profile: &Profile, pw: Option<&str>) -> Result<()> {
    let hash = write(vault, name, profile)?;
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    let mut hashes = meta.sandbox_seccomp_profile_hash.clone().unwrap_or_default();
    hashes.insert(name.to_string(), hash);
    meta.sandbox_seccomp_profile_hash = Some(hashes);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    Ok(())
}

/// Every target key (`_root` or a rootfs environment name) currently
/// pointed at this profile.
fn referencing_targets(meta: &Meta, name: &str) -> Vec<String> {
    meta.sandbox_seccomp.as_ref().map(|m| m.iter().filter(|(_, v)| v.as_str() == name).map(|(k, _)| k.clone()).collect()).unwrap_or_default()
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("list") => list(ctx, vault),
        Some("create") => {
            let Some(name) = extra.get(1) else {
                die!("usage: cas <vault> settings security sandbox seccomp custom create <name>");
            };
            create(ctx, vault, name, pw)
        }
        Some("delete") => {
            let Some(name) = extra.get(1) else {
                die!("usage: cas <vault> settings security sandbox seccomp custom delete <name>");
            };
            delete(ctx, vault, name, pw)
        }
        Some("rename") => {
            let (Some(old), Some(new)) = (extra.get(1), extra.get(2)) else {
                die!("usage: cas <vault> settings security sandbox seccomp custom rename <old> <new>");
            };
            rename(ctx, vault, old, new, pw)
        }
        Some("edit") => {
            let Some(name) = extra.get(1) else {
                die!("usage: cas <vault> settings security sandbox seccomp custom edit <name> [default <allow|deny>|add ...|remove ...|status]");
            };
            edit_dispatch(ctx, vault, name, &extra[2..], pw)
        }
        _ => die!("usage: cas <vault> settings security sandbox seccomp custom list|create <name>|delete <name>|rename <old> <new>|edit <name> ..."),
    }
}

fn list(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let d = dir(vault);
    if !d.exists() {
        logf!(ctx, "  no custom seccomp profiles yet -- create one with:  cas {} settings security sandbox seccomp custom create <name>", vault.name);
        return Ok(());
    }
    let mut names: Vec<String> = fs::read_dir(&d)?
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter_map(|n| n.strip_suffix(".toml").map(str::to_string))
        .collect();
    names.sort();
    if names.is_empty() {
        logf!(ctx, "  no custom seccomp profiles yet -- create one with:  cas {} settings security sandbox seccomp custom create <name>", vault.name);
        return Ok(());
    }
    let meta = Meta::read(&vault.img);
    for name in names {
        let targets = referencing_targets(&meta, &name);
        let used_by = if targets.is_empty() { "unused".to_string() } else { format!("used by: {}", targets.join(", ")) };
        logf!(ctx, "  {name}  [{used_by}]");
    }
    Ok(())
}

/// A `default = "deny"` profile blocks everything not explicitly
/// allowed -- including the syscalls `exec`'s own PID1 supervisor needs
/// for its own bookkeeping (`getpid`/`wait4`/`kill`/`fork`/`clone`/
/// `exit_group`), not just whatever command is actually being run. A
/// profile missing those will make `exec` fail outright with a
/// confusing low-level error (see `sandbox::reaper::run_as_pid1`'s own
/// handling of this) rather than a clean seccomp-specific one -- this
/// warns proactively, at the point the profile becomes default-deny,
/// rather than only after the fact.
fn warn_default_deny(ctx: &Ctx, profile_name: &str) {
    logf!(
        ctx,
        "  [i] '{profile_name}' denies by default -- make sure its allow list also covers getpid, wait4, kill, fork, clone, and exit_group, which exec's own sandbox supervisor needs regardless of what command is being run"
    );
}

fn create(ctx: &Ctx, vault: &Vault, profile_name: &str, pw: Option<&str>) -> Result<()> {
    name::validate("seccomp profile", profile_name)?;
    if crate::registry::seccomp::PRESET_NAMES.contains(&profile_name) {
        die!("'{profile_name}' is a built-in seccomp preset name -- custom profiles can't reuse it, since `seccomp set` resolves both from one shared namespace");
    }
    if exists(vault, profile_name) {
        die!("custom seccomp profile '{profile_name}' already exists -- 'seccomp custom edit {profile_name}' to change it");
    }
    save(ctx, vault, profile_name, &Profile::default(), pw)?;
    logf!(ctx, "[✓] custom seccomp profile '{profile_name}' created (default: deny, empty allow/deny lists)");
    warn_default_deny(ctx, profile_name);
    Ok(())
}

fn delete(ctx: &Ctx, vault: &Vault, profile_name: &str, pw: Option<&str>) -> Result<()> {
    if crate::registry::seccomp::PRESET_NAMES.contains(&profile_name) {
        die!("'{profile_name}' is a built-in seccomp preset, not a custom profile -- built-ins can't be edited or deleted");
    }
    if !exists(vault, profile_name) {
        die!("custom seccomp profile '{profile_name}' doesn't exist -- see 'seccomp custom list'");
    }
    let meta = Meta::read(&vault.img);
    let targets = referencing_targets(&meta, profile_name);
    if !targets.is_empty() {
        die!("custom seccomp profile '{profile_name}' is still used by: {} -- point them at a different preset first ('seccomp set <preset>')", targets.join(", "));
    }
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = meta;
    fs::remove_file(path(vault, profile_name))?;
    if let Some(hashes) = meta.sandbox_seccomp_profile_hash.as_mut() {
        hashes.remove(profile_name);
    }
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] custom seccomp profile '{profile_name}' deleted");
    Ok(())
}

fn rename(ctx: &Ctx, vault: &Vault, old: &str, new: &str, pw: Option<&str>) -> Result<()> {
    name::validate("seccomp profile", new)?;
    if crate::registry::seccomp::PRESET_NAMES.contains(&new) {
        die!("'{new}' is a built-in seccomp preset name -- custom profiles can't reuse it, since `seccomp set` resolves both from one shared namespace");
    }
    if !exists(vault, old) {
        die!("custom seccomp profile '{old}' doesn't exist -- see 'seccomp custom list'");
    }
    if exists(vault, new) {
        die!("custom seccomp profile '{new}' already exists");
    }
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    fs::rename(path(vault, old), path(vault, new))?;

    let mut meta = Meta::read(&vault.img);
    if let Some(hashes) = meta.sandbox_seccomp_profile_hash.as_mut() {
        if let Some(h) = hashes.remove(old) {
            hashes.insert(new.to_string(), h);
        }
    }
    if let Some(targets) = meta.sandbox_seccomp.as_mut() {
        for v in targets.values_mut() {
            if v.as_str() == old {
                *v = new.to_string();
            }
        }
    }
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] custom seccomp profile '{old}' renamed to '{new}'");
    Ok(())
}

fn edit_dispatch(ctx: &Ctx, vault: &Vault, profile_name: &str, rest: &[String], pw: Option<&str>) -> Result<()> {
    if crate::registry::seccomp::PRESET_NAMES.contains(&profile_name) {
        die!("'{profile_name}' is a built-in seccomp preset, not a custom profile -- built-ins can't be edited or deleted");
    }
    if !exists(vault, profile_name) {
        die!("custom seccomp profile '{profile_name}' doesn't exist -- create it first: 'seccomp custom create {profile_name}'");
    }
    match rest.first().map(String::as_str) {
        None => edit_raw(ctx, vault, profile_name, pw),
        Some("default") => {
            let Some(action) = rest.get(1) else {
                die!("usage: cas <vault> settings security sandbox seccomp custom edit {profile_name} default <allow|deny>");
            };
            edit_default(ctx, vault, profile_name, action, pw)
        }
        Some("add") => edit_add_remove(ctx, vault, profile_name, &rest[1..], pw, true),
        Some("remove") => edit_add_remove(ctx, vault, profile_name, &rest[1..], pw, false),
        Some("status") => status(ctx, vault, profile_name),
        Some(other) => die!("unknown 'seccomp custom edit' action '{other}' -- expected default|add|remove|status, or no action to open $EDITOR"),
    }
}

fn edit_raw(ctx: &Ctx, vault: &Vault, profile_name: &str, pw: Option<&str>) -> Result<()> {
    let p = path(vault, profile_name);
    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "vi".to_string());
    let status = std::process::Command::new(&editor).arg(&p).status()?;
    if !status.success() {
        die!("'{editor}' exited with an error -- profile '{profile_name}' not updated");
    }
    // Re-parse to validate before recording a hash for it -- a syntax
    // error or invalid `default` value shouldn't silently get treated
    // as a trusted, hash-verified profile.
    let profile = read(vault, profile_name)?;
    if profile.default != "allow" && profile.default != "deny" {
        die!("profile '{profile_name}': `default` must be \"allow\" or \"deny\", got \"{}\"", profile.default);
    }
    check_conflicts(&profile)?;
    save(ctx, vault, profile_name, &profile, pw)?;
    logf!(ctx, "[✓] custom seccomp profile '{profile_name}' updated");
    Ok(())
}

fn edit_default(ctx: &Ctx, vault: &Vault, profile_name: &str, action: &str, pw: Option<&str>) -> Result<()> {
    if action != "allow" && action != "deny" {
        die!("usage: cas <vault> settings security sandbox seccomp custom edit {profile_name} default <allow|deny>");
    }
    let mut profile = read(vault, profile_name)?;
    profile.default = action.to_string();
    save(ctx, vault, profile_name, &profile, pw)?;
    logf!(ctx, "[✓] '{profile_name}' default action set to '{action}'");
    if action == "deny" {
        warn_default_deny(ctx, profile_name);
    }
    Ok(())
}

/// Shared by `add`/`remove` -- parses `--allow <list>`/`--deny <list>`
/// (either order, each flag scopes the comma-separated list that
/// immediately follows it), with a bare list and no flag meaning
/// `--allow` (matches this feature's original allowlist-only behavior).
fn parse_scoped_lists(rest: &[String]) -> Result<(Vec<String>, Vec<String>)> {
    let mut allow_raw: Option<&str> = None;
    let mut deny_raw: Option<&str> = None;
    let mut i = 0;
    let mut bare: Option<&str> = None;
    while i < rest.len() {
        match rest[i].as_str() {
            "--allow" => {
                let Some(v) = rest.get(i + 1) else {
                    die!("--allow needs a comma-separated list of syscall names/ids");
                };
                allow_raw = Some(v);
                i += 2;
            }
            "--deny" => {
                let Some(v) = rest.get(i + 1) else {
                    die!("--deny needs a comma-separated list of syscall names/ids");
                };
                deny_raw = Some(v);
                i += 2;
            }
            other => {
                if bare.is_some() || allow_raw.is_some() || deny_raw.is_some() {
                    die!("unexpected argument '{other}' -- usage: add|remove [--allow <list>] [--deny <list>]");
                }
                bare = Some(other);
                i += 1;
            }
        }
    }
    if let Some(b) = bare {
        allow_raw = Some(b);
    }
    if allow_raw.is_none() && deny_raw.is_none() {
        die!("nothing to do -- give a bare list (treated as --allow), or --allow/--deny explicitly");
    }
    let allow = match allow_raw {
        Some(s) => resolve_list(s)?,
        None => Vec::new(),
    };
    let deny = match deny_raw {
        Some(s) => resolve_list(s)?,
        None => Vec::new(),
    };
    Ok((allow, deny))
}

fn resolve_list(raw: &str) -> Result<Vec<String>> {
    raw.split(',').map(str::trim).filter(|s| !s.is_empty()).map(resolve_syscall_token).collect()
}

/// A token is either a syscall name (validated against the host's own
/// architecture table) or a numeric id, auto-resolved to that id's
/// canonical name on this host's architecture -- the on-disk profile
/// always stores names, never raw numbers, so it stays portable and
/// human-readable regardless of what a user typed.
fn resolve_syscall_token(token: &str) -> Result<String> {
    let Some(table) = syscall_table::for_host_arch() else {
        die!("no seccomp syscall table for this architecture ({}) -- can't validate syscall names/ids", std::env::consts::ARCH);
    };
    if let Ok(id) = token.parse::<i64>() {
        return table.iter().find(|(_, &v)| v == id).map(|(name, _)| name.clone()).ok_or_else(|| crate::error::CasError::new(format!("no syscall with number {id} on this architecture")));
    }
    if table.contains_key(token) {
        return Ok(token.to_string());
    }
    die!("unknown syscall '{token}'");
}

fn check_conflicts(profile: &Profile) -> Result<()> {
    for s in &profile.allow {
        if profile.deny.contains(s) {
            die!("syscall '{s}' can't be in both the allow and deny list");
        }
    }
    Ok(())
}

fn edit_add_remove(ctx: &Ctx, vault: &Vault, profile_name: &str, rest: &[String], pw: Option<&str>, adding: bool) -> Result<()> {
    let (allow, deny) = parse_scoped_lists(rest)?;
    let mut profile = read(vault, profile_name)?;

    if adding {
        for s in &allow {
            if !profile.allow.contains(s) {
                profile.allow.push(s.clone());
            }
        }
        for s in &deny {
            if !profile.deny.contains(s) {
                profile.deny.push(s.clone());
            }
        }
    } else {
        profile.allow.retain(|s| !allow.contains(s));
        profile.deny.retain(|s| !deny.contains(s));
    }
    profile.allow.sort();
    profile.deny.sort();
    check_conflicts(&profile)?;

    save(ctx, vault, profile_name, &profile, pw)?;
    let verb = if adding { "added to" } else { "removed from" };
    logf!(ctx, "[✓] syscalls {verb} '{profile_name}'");
    Ok(())
}

fn status(ctx: &Ctx, vault: &Vault, profile_name: &str) -> Result<()> {
    let profile = read(vault, profile_name)?;
    logf!(ctx, "  '{profile_name}': default={}", profile.default);
    if profile.allow.is_empty() {
        logf!(ctx, "    allow: (none)");
    } else {
        logf!(ctx, "    allow: {}", profile.allow.join(", "));
    }
    if profile.deny.is_empty() {
        logf!(ctx, "    deny:  (none)");
    } else {
        logf!(ctx, "    deny:  {}", profile.deny.join(", "));
    }
    Ok(())
}
