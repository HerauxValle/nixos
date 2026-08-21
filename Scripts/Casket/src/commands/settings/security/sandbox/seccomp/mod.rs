// &desc: "`cas <vault> settings security sandbox seccomp [--rootfs <name>] set <preset>|state` -- which syscall filter applies to a given target (a named rootfs environment, or the zero-rootfs '_root' case). Built-in presets (default/strict/compute/none) and named custom profiles share one flat namespace -- `set <name>` resolves either the same way, activation doesn't care which kind a name is. The only asymmetry is that custom profiles (managed under `seccomp custom`, see `profiles` submodule) can be edited/deleted/renamed and built-ins can't -- they're compiled into the binary, not real files. `profiles::create`/`rename` refuse any name that collides with a built-in, so the two namespaces can never actually clash."
use crate::cli_registry::{self, Domain, Resolved};
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::rootfs;
use crate::commands::settings::security::sandbox::rootfs::ROOT_KEY;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::registry;
use crate::tamper;
use crate::vault::Vault;

pub mod profiles;

/// This subtree's own flat, position-independent id space -- see
/// `network.rs`'s doc comment (the reference implementation this
/// module follows) for the full reasoning on why each variant is a
/// bare number, not a semantic name.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code2200,
    Code2201,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[("2200", ActionId::Code2200), ("2201", ActionId::Code2201)];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Finds the `seccomp` node inside the compiled-in registry tree
/// (`settings -> security -> sandbox -> seccomp`) once. Only `set` and
/// `state` live here -- `custom` is routed to `profiles::dispatch`
/// before this is ever consulted (see `dispatch` below).
fn seccomp_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| {
            let path = ["settings", "security", "sandbox", "seccomp"];
            let mut nodes = cli_registry::get().vault.as_slice();
            for name in path {
                nodes = nodes.iter().find(|n| n.name == name).map(|n| n.children.as_slice()).unwrap_or(&[]);
            }
            nodes.to_vec()
        })
        .as_slice()
}

pub fn target_key(vault: &Vault, explicit_rootfs: Option<&str>) -> Result<String> {
    Ok(rootfs::resolve(vault, explicit_rootfs)?.unwrap_or_else(|| ROOT_KEY.to_string()))
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    // `custom` management is target-independent (a profile is vault-
    // wide, reusable across every target), so it's checked before
    // `--rootfs` parsing even applies.
    if extra.first().map(String::as_str) == Some("custom") {
        return profiles::dispatch(ctx, vault, &extra[1..], pw);
    }

    let (explicit_rootfs, rest) = if extra.first().map(String::as_str) == Some("--rootfs") {
        let Some(name) = extra.get(1) else {
            die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set <preset> | state");
        };
        (Some(name.as_str()), &extra[2..])
    } else {
        (None, &extra[..])
    };

    let tokens: Vec<&str> = rest.iter().map(String::as_str).collect();
    match cli_registry::resolve(seccomp_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, explicit_rootfs, &rest[consumed..], pw)
        }
        // A bare `seccomp` (no `set`/`state` token at all) defaults to
        // `state`, same as before this was tree-driven.
        Resolved::Branch(_) | Resolved::NotFound if rest.is_empty() => state(ctx, vault, explicit_rootfs),
        _ => die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set <preset> | state | custom ..."),
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, explicit_rootfs: Option<&str>, rest: &[String], pw: Option<&str>) -> Result<()> {
    match id {
        ActionId::Code2200 => {
            let Some(preset) = rest.first() else {
                die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set <default|strict|compute|none|profile-name>");
            };
            set(ctx, vault, explicit_rootfs, preset, pw)
        }
        ActionId::Code2201 => state(ctx, vault, explicit_rootfs),
    }
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation --
/// see `commands::debug`. `profiles` self-registers its own ids
/// independently (see that module), so this only needs its own.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }

/// A bare name resolves to either a built-in preset or a custom
/// profile -- whichever exists, since `profiles::create`/`rename`
/// refuse any name that collides with a built-in (see this module's
/// own doc comment). No prefix needed to disambiguate.
fn set(ctx: &Ctx, vault: &Vault, explicit_rootfs: Option<&str>, preset: &str, pw: Option<&str>) -> Result<()> {
    if !registry::seccomp::PRESET_NAMES.contains(&preset) && !profiles::exists(vault, preset) {
        die!("unknown seccomp preset or custom profile '{preset}' -- expected one of: default, strict, compute, none, or a custom profile name (see 'seccomp custom list')");
    }

    let key = target_key(vault, explicit_rootfs)?;
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    let mut map = meta.sandbox_seccomp.clone().unwrap_or_default();
    map.insert(key.clone(), preset.to_string());
    meta.sandbox_seccomp = Some(map);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;

    logf!(ctx, "[✓] seccomp set to '{preset}' for {}", target_label(&key));
    Ok(())
}

fn state(ctx: &Ctx, vault: &Vault, explicit_rootfs: Option<&str>) -> Result<()> {
    let key = target_key(vault, explicit_rootfs)?;
    let meta = Meta::read(&vault.img);
    let preset = meta.sandbox_seccomp.as_ref().and_then(|m| m.get(&key)).cloned().unwrap_or_else(|| "default".to_string());
    logf!(ctx, "  {}: {preset}", target_label(&key));
    Ok(())
}

fn target_label(key: &str) -> String {
    if key == ROOT_KEY {
        "the vault's own content (no named rootfs)".to_string()
    } else {
        format!("rootfs '{key}'")
    }
}
