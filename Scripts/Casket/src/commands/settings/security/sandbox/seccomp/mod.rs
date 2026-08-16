// &desc: "`cas <vault> settings security sandbox seccomp [--rootfs <name>] set <preset>|state` -- which syscall filter applies to a given target (a named rootfs environment, or the zero-rootfs '_root' case). Built-in presets (default/strict/compute/none) come from registry::seccomp; a named custom profile is referenced as `custom:<name>` and managed separately, see `profiles` submodule."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::rootfs;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::registry;
use crate::tamper;
use crate::vault::Vault;

pub mod profiles;

/// The map key `sandbox_seccomp`/target lookups use for the zero-rootfs
/// case -- `exec` pivots into the vault's own content directly then, so
/// it still needs *a* seccomp target, just not one named after a real
/// rootfs environment. Not a valid environment name itself (see
/// `rootfs::RESERVED_NAMES`), so it can't collide.
const ROOT_KEY: &str = "_root";

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

    match rest.first().map(String::as_str) {
        Some("set") => {
            let Some(preset) = rest.get(1) else {
                die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set <default|strict|compute|none|custom:<profile>>");
            };
            set(ctx, vault, explicit_rootfs, preset, pw)
        }
        Some("state") | None => state(ctx, vault, explicit_rootfs),
        _ => die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set <preset> | state | custom ..."),
    }
}

fn set(ctx: &Ctx, vault: &Vault, explicit_rootfs: Option<&str>, preset: &str, pw: Option<&str>) -> Result<()> {
    if let Some(profile_name) = preset.strip_prefix("custom:") {
        if !profiles::exists(vault, profile_name) {
            die!("no custom seccomp profile named '{profile_name}' -- create it first: 'seccomp custom create {profile_name}' (see 'seccomp custom list')");
        }
    } else if !registry::seccomp::PRESET_NAMES.contains(&preset) {
        die!(
            "unknown seccomp preset '{preset}' -- expected one of: default, strict, compute, none, or custom:<profile> (see 'seccomp custom list')"
        );
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
