// &desc: "`cas <vault> settings security sandbox seccomp custom list|create|delete|rename|edit` -- named, reusable custom seccomp profiles. Each profile is its own TOML file under `.seccomp.d/` (mode-independent: an `allow` list, a `deny` list, and a `default` action for anything in neither), referenced by any target via the same flat `seccomp set <name>` built-ins use -- no prefix. `create`/`rename` refuse any name colliding with a built-in preset, so the shared namespace never actually clashes. Replaces the older one-per-target-only custom file (see migrations::v3)."
use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::cli_registry::Domain;
use crate::cli_registry::{self, Resolved};
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

/// This subtree's own flat, position-independent id space -- see
/// `network.rs`'s doc comment (the reference implementation this
/// module follows) for the full reasoning. `EditRaw` covers the bare
/// `edit <name>` (no further token) case, which opens `$EDITOR` --
/// it's a real leaf conceptually, but tree-wise `edit` is a branch
/// (its children are `default`/`add`/`remove`/`status`), so it's never
/// reached via `cli_registry::resolve`'s `Leaf` arm. It's still given
/// an id here (and a `cli/codes.kdl` entry + help page) purely for
/// documentation/help-text consistency; dispatch below wires it in
/// directly rather than through `ActionId::from_code`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code2202,
    Code2203,
    Code2204,
    Code2205,
    Code2207,
    Code2208,
    Code2209,
    Code2210,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[
        ("2202", ActionId::Code2202),
        ("2203", ActionId::Code2203),
        ("2204", ActionId::Code2204),
        ("2205", ActionId::Code2205),
        ("2207", ActionId::Code2207),
        ("2208", ActionId::Code2208),
        ("2209", ActionId::Code2209),
        ("2210", ActionId::Code2210),
    ];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    pub fn known_codes() -> Vec<&'static str> {
        // "2206" (the bare `edit <name>` / EditRaw case) is included
        // here even though it has no `ActionId` variant -- it's a
        // deliberate, documented gap (see this enum's doc comment),
        // not a forgotten wire-up, so it must not show up in `debug
        // parse-cli`'s Ignored list.
        let mut all: Vec<&'static str> = Self::ALL.iter().map(|(c, _)| *c).collect();
        all.push("2206");
        all
    }
}

/// Finds the `custom` node inside the compiled-in registry tree
/// (`settings -> security -> sandbox -> seccomp -> custom`) once.
fn custom_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| {
            let path = ["settings", "security", "sandbox", "seccomp", "custom"];
            let mut nodes = cli_registry::get().vault.as_slice();
            for name in path {
                nodes = nodes.iter().find(|n| n.name == name).map(|n| n.children.as_slice()).unwrap_or(&[]);
            }
            nodes.to_vec()
        })
        .as_slice()
}

/// Finds the `edit` node's own children (`default`/`add`/`remove`/
/// `status`) once -- one level deeper than `custom_children`.
fn edit_children() -> &'static [cli_registry::TreeNode] {
    custom_children().iter().find(|n| n.name == "edit").map(|n| n.children.as_slice()).unwrap_or(&[])
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation --
/// see `commands::debug` and `seccomp::known_ids` (which folds this
/// in alongside its own top-level `set`/`state` ids).
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }

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
    // `edit <name> ...` is handled before `resolve()` ever sees it:
    // the profile name sits right after `edit` in argv, but it isn't a
    // tree node (it's vault-supplied data, same as `create <name>`'s
    // name), so `resolve()` can only walk as far as the `edit` branch
    // itself. See `edit_dispatch` for the rest of the navigation, one
    // level deeper, over `default`/`add`/`remove`/`status`.
    if extra.first().map(String::as_str) == Some("edit") {
        let Some(name) = extra.get(1) else {
            die!("usage: cas <vault> settings security sandbox seccomp custom edit <name> [default <allow|deny>|add ...|remove ...|status]");
        };
        return edit_dispatch(ctx, vault, name, &extra[2..], pw);
    }

    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(custom_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..], pw)
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> settings security sandbox seccomp custom list|create <name>|delete <name>|rename <old> <new>|edit <name> ...")
        }
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, rest: &[String], pw: Option<&str>) -> Result<()> {
    match id {
        ActionId::Code2202 => list(ctx, vault),
        ActionId::Code2203 => {
            let Some(name) = rest.first() else {
                die!("usage: cas <vault> settings security sandbox seccomp custom create <name>");
            };
            create(ctx, vault, name, pw)
        }
        ActionId::Code2204 => {
            let Some(name) = rest.first() else {
                die!("usage: cas <vault> settings security sandbox seccomp custom delete <name>");
            };
            delete(ctx, vault, name, pw)
        }
        ActionId::Code2205 => {
            let (Some(old), Some(new)) = (rest.first(), rest.get(1)) else {
                die!("usage: cas <vault> settings security sandbox seccomp custom rename <old> <new>");
            };
            rename(ctx, vault, old, new, pw)
        }
        // `edit`'s own sub-actions never reach here -- they're
        // dispatched by `edit_dispatch` directly, since the profile
        // name sitting between `edit` and the sub-action means the
        // top-level `resolve()` above never walks deep enough to
        // reach them.
        ActionId::Code2207 | ActionId::Code2208 | ActionId::Code2209 | ActionId::Code2210 => {
            unreachable!("edit sub-action ids are dispatched via edit_dispatch, not the top-level custom resolve()")
        }
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

/// One level deeper than `dispatch`'s own `resolve()` call -- walks
/// `default`/`add`/`remove`/`status` against `edit`'s children in the
/// tree. `rest` here is already past `edit <name>` (both consumed
/// manually by `dispatch`, since `<name>` isn't a tree node), so an
/// empty `rest` means the bare `edit <name>` form -- open `$EDITOR`.
fn edit_dispatch(ctx: &Ctx, vault: &Vault, profile_name: &str, rest: &[String], pw: Option<&str>) -> Result<()> {
    if crate::registry::seccomp::PRESET_NAMES.contains(&profile_name) {
        die!("'{profile_name}' is a built-in seccomp preset, not a custom profile -- built-ins can't be edited or deleted");
    }
    if !exists(vault, profile_name) {
        die!("custom seccomp profile '{profile_name}' doesn't exist -- create it first: 'seccomp custom create {profile_name}'");
    }
    if rest.is_empty() {
        return edit_raw(ctx, vault, profile_name, pw);
    }
    let tokens: Vec<&str> = rest.iter().map(String::as_str).collect();
    match cli_registry::resolve(edit_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            let sub_rest = &rest[consumed..];
            match id {
                ActionId::Code2207 => {
                    let Some(action) = sub_rest.first() else {
                        die!("usage: cas <vault> settings security sandbox seccomp custom edit {profile_name} default <allow|deny>");
                    };
                    edit_default(ctx, vault, profile_name, action, pw)
                }
                ActionId::Code2208 => edit_add_remove(ctx, vault, profile_name, sub_rest, pw, true),
                ActionId::Code2209 => edit_add_remove(ctx, vault, profile_name, sub_rest, pw, false),
                ActionId::Code2210 => status(ctx, vault, profile_name),
                _ => unreachable!("edit_children() only yields default/add/remove/status ids"),
            }
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("unknown 'seccomp custom edit' action -- expected default|add|remove|status, or no action to open $EDITOR")
        }
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
