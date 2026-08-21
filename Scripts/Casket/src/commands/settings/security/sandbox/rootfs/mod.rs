// &desc: "`cas <vault> settings security sandbox rootfs list|add|update|remove|rename|default` -- named rootfs environments for `exec --rootfs <name>`. `.rootfs.d/` is created lazily as a real btrfs subvolume the first time any rootfs subcommand runs, not by a migration -- most vaults never use this feature, so nothing about it should touch a vault that doesn't opt in."
use std::fs;
use std::path::PathBuf;

mod add;
mod default;
mod remove;
mod rename;
mod update;

use crate::cli_registry::Domain;
use crate::btrfs;
use crate::cli_registry::{self, Resolved};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::udisks;
use crate::vault::Vault;

/// This subtree's own flat, position-independent id space -- see
/// `network.rs`'s doc comment (the reference implementation this
/// pattern is copied from) for the full reasoning.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code1700,
    Code1701,
    Code1702,
    Code1703,
    Code1704,
    Code1705,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[
        ("1700", ActionId::Code1700),
        ("1701", ActionId::Code1701),
        ("1702", ActionId::Code1702),
        ("1703", ActionId::Code1703),
        ("1704", ActionId::Code1704),
        ("1705", ActionId::Code1705),
    ];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    /// Every code this domain knows how to handle -- consulted only by
    /// `cas debug parse-cli` (via `commands::debug::*_known_ids`) to
    /// compute the Ignored list, never by dispatch itself.
    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Finds the `rootfs` node inside the compiled-in registry tree
/// (`settings -> security -> sandbox -> rootfs`) once. If this ever
/// returns `None` it means `cli/registry.kdl` and this file's hardcoded
/// navigation path have drifted apart -- a build-time/test bug, not
/// something a user can trigger, hence the `expect`.
fn rootfs_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| {
            let path = ["settings", "security", "sandbox", "rootfs"];
            let mut nodes = cli_registry::get().vault.as_slice();
            for name in path {
                nodes = nodes.iter().find(|n| n.name == name).map(|n| n.children.as_slice()).unwrap_or(&[]);
            }
            nodes.to_vec()
        })
        .as_slice()
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation --
/// see `commands::debug`.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }

/// Reserved across every rootfs subcommand that takes a name -- `all`
/// is the `--removeRootfs`/`remove` wildcard keyword (never a glob, to
/// avoid shell expansion surprises), `default` would collide with the
/// `default` verb/symlink itself.
pub const RESERVED_NAMES: &[&str] = &["all", "default", ROOT_KEY];

/// Sentinel meaning "the vault's own content, not any rootfs
/// environment" -- accepted anywhere a rootfs name is (`--rootfs
/// _root`), resolved specially in `resolve()` below rather than looked
/// up as a real directory. Exists so `exec`/`seccomp` can explicitly
/// target the vault's own root even when exactly one real environment
/// exists and would otherwise be auto-selected (see `resolve`'s doc
/// comment) -- without this, there was no way to reach that target
/// once any environment existed at all. Reserved here (not just used
/// by `seccomp`, which originally defined its own private copy of this
/// same string) so `add`/`rename` can never create a real environment
/// that collides with it.
pub const ROOT_KEY: &str = "_root";

/// Rejects any environment name that could escape `.rootfs.d/` once
/// joined onto a directory path with `.join(name)` -- no path
/// separators, no `.`/`..` component tricks, not empty. Every call site
/// across this module that does `dir.join(name)` with a caller-supplied
/// name (`add`, `update`, `remove`, `rename`'s old *and* new, `default`,
/// `resolve`'s explicit-name branch) must validate through this first --
/// skipping it at even one of them reopens the exact path-traversal bug
/// this closes (a name like `../../etc` previously reached real
/// filesystem writes, including a root-privileged recursive `chown`, at
/// an arbitrary host path).
pub fn validate_name(name: &str) -> Result<()> {
    if name.is_empty() {
        die!("rootfs environment name can't be empty");
    }
    if name == "." || name == ".." {
        die!("'{name}' isn't a valid rootfs environment name");
    }
    if name.starts_with('.') || name.ends_with('.') {
        die!("rootfs environment name '{name}' can't start or end with '.'");
    }
    if !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.') {
        die!(
            "rootfs environment name '{name}' contains an invalid character -- only letters, digits, '-', '_', and '.' are allowed"
        );
    }
    Ok(())
}

const DEFAULT_SYMLINK: &str = "default";

/// Ensures `.rootfs.d/` exists as a real subvolume (creating it, chowned
/// to the real user, on first call) and returns its path. Idempotent --
/// a no-op once it's already there. `.rootfs.d/` deliberately isn't
/// subject to ransomwareProtection's lock (see `Vault::rootfs_dir`'s doc
/// comment), so it's chowned to the real user unconditionally, not
/// gated on that setting the way `.casket/` is.
pub fn ensure_dir(vault: &Vault) -> Result<PathBuf> {
    let dir = vault.rootfs_dir();
    if !dir.exists() {
        btrfs::subvolume_create(&dir)?;
        udisks::chown_to_real_user(&dir)?;
    }
    Ok(dir)
}

/// The current `default` environment's name, or `None` if unset,
/// dangling (points at something that no longer exists), or -- the
/// security-relevant case -- resolves outside `.rootfs.d/` entirely.
/// The symlink's target is plain user/attacker-writable filesystem
/// state feeding directly into what `exec` later pivot_roots into, so
/// it's canonicalized and containment-checked here, once, rather than
/// trusted at every call site.
pub fn default_target(vault: &Vault) -> Option<String> {
    let dir = vault.rootfs_dir();
    let link = dir.join(DEFAULT_SYMLINK);
    let resolved = fs::canonicalize(&link).ok()?;
    let dir_canon = fs::canonicalize(&dir).ok()?;
    if resolved.parent() != Some(dir_canon.as_path()) {
        return None; // escapes .rootfs.d/ -- treat exactly like "unset"
    }
    resolved.file_name()?.to_str().map(str::to_string)
}

/// Sets (`Some(name)`) or clears (`None`) the `default` symlink. A
/// plain filesystem symlink, not a metadata field -- `ln -sfn` inside
/// the mounted vault would do the same thing by hand.
pub fn set_default(vault: &Vault, name: Option<&str>) -> Result<()> {
    let dir = ensure_dir(vault)?;
    let link = dir.join(DEFAULT_SYMLINK);
    let _ = fs::remove_file(&link);
    if let Some(name) = name {
        std::os::unix::fs::symlink(name, &link)?;
    }
    Ok(())
}

/// Which rootfs environment (if any) a caller should use, per the one
/// resolution rule shared by `exec --rootfs` and `seccomp --rootfs`: an
/// explicit `<name>` always wins (with `--rootfs _root`/`ROOT_KEY`
/// short-circuiting straight to "the vault's own content", the only way
/// to reach that target once any real environment exists and would
/// otherwise be auto-selected below); otherwise zero environments means
/// `Ok(None)` (isolate the vault's own content directly / target the
/// `_root` sentinel), exactly one is used automatically, and multiple
/// environments use the `default` symlink target if one's set -- or
/// refuse, listing the available names, if not.
pub fn resolve(vault: &Vault, explicit: Option<&str>) -> Result<Option<String>> {
    if explicit == Some(ROOT_KEY) {
        return Ok(None);
    }
    if let Some(name) = explicit {
        validate_name(name)?;
        let dir = ensure_dir(vault)?;
        if !dir.join(name).exists() {
            die!("rootfs environment '{name}' doesn't exist -- see 'cas <vault> settings security sandbox rootfs list'");
        }
        return Ok(Some(name.to_string()));
    }

    let dir = vault.rootfs_dir();
    if !dir.exists() {
        return Ok(None);
    }
    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();

    match names.len() {
        0 => Ok(None),
        1 => Ok(Some(names.remove(0))),
        _ => match default_target(vault) {
            Some(name) => Ok(Some(name)),
            None => die!(
                "multiple rootfs environments exist ({}) -- specify one with --rootfs <name>, or set a default: settings security sandbox rootfs default <name>",
                names.join(", ")
            ),
        },
    }
}

/// Removes every rootfs environment -- the same `all` wildcard `rootfs
/// remove all` itself uses (see `RESERVED_NAMES`'s doc comment), reused
/// here so `sandbox disable --removeRootfs` gets identical behavior:
/// typed per-environment confirmation, refuses while any environment
/// is live-in-use, and refuses if a `default` is still set (removal
/// deliberately doesn't auto-clear it -- see `remove.rs`'s own doc
/// comment on why that's not an implicit side effect this takes).
pub fn remove_all(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    remove::dispatch(ctx, vault, &["all".to_string()], pw)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    // `rootfs` with no subcommand at all defaults to `list` -- kept as
    // a direct check ahead of registry resolution since `resolve()`
    // walks tokens and has nothing to match against on an empty slice.
    if extra.is_empty() {
        return list(ctx, vault);
    }
    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(rootfs_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..], pw)
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> settings security sandbox rootfs list|add|update|remove|rename|default ...")
        }
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, rest: &[String], pw: Option<&str>) -> Result<()> {
    match id {
        ActionId::Code1700 => list(ctx, vault),
        ActionId::Code1701 => add::dispatch(ctx, vault, rest, pw),
        ActionId::Code1702 => update::dispatch(ctx, vault, rest, pw),
        ActionId::Code1703 => remove::dispatch(ctx, vault, rest, pw),
        ActionId::Code1704 => rename::dispatch(ctx, vault, rest, pw),
        ActionId::Code1705 => default::dispatch(ctx, vault, rest, pw),
    }
}

fn list(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let dir = ensure_dir(vault)?;
    let mut names: Vec<String> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();

    if names.is_empty() {
        logf!(ctx, "[i] no rootfs environments yet -- see 'cas help exec'");
        return Ok(());
    }
    let default = default_target(vault);
    for name in names {
        if default.as_deref() == Some(name.as_str()) {
            logf!(ctx, "  {name} (default)");
        } else {
            logf!(ctx, "  {name}");
        }
    }
    Ok(())
}
