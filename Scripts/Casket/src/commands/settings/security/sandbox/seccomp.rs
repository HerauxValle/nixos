// &desc: "`cas <vault> settings security sandbox seccomp [--rootfs <name>] set <preset>|edit <preset>|state` -- which syscall filter (if any) applies to a given rootfs environment (or the zero-rootfs '_root' case). Enforcement itself doesn't exist yet (next slice) -- this is storage + the custom-file edit flow only."
use std::fs;

use sha2::{Digest, Sha256};

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

/// The map key `sandbox_seccomp`/`sandbox_seccomp_custom_hash` use for
/// the zero-rootfs case -- `exec` pivots into the vault's own content
/// directly then, so it still needs *a* seccomp target, just not one
/// named after a real rootfs environment. Not a valid environment name
/// itself (see `rootfs::RESERVED_NAMES`), so it can't collide.
const ROOT_KEY: &str = "_root";

pub fn target_key(vault: &Vault, explicit_rootfs: Option<&str>) -> Result<String> {
    Ok(rootfs::resolve(vault, explicit_rootfs)?.unwrap_or_else(|| ROOT_KEY.to_string()))
}

/// Where a target's custom syscall list lives on disk -- inside the
/// environment for a named rootfs, at the vault's top level (sibling to
/// `.rootfs.d/`, matching where `.rootfs.d/` itself sits) for `_root`.
pub fn custom_file_path(vault: &Vault, key: &str) -> std::path::PathBuf {
    if key == ROOT_KEY {
        vault.mnt.join(".casket-seccomp")
    } else {
        vault.rootfs_dir().join(key).join(".casket-seccomp")
    }
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let (explicit_rootfs, rest) = if extra.first().map(String::as_str) == Some("--rootfs") {
        let Some(name) = extra.get(1) else {
            die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set|edit <preset> | state");
        };
        (Some(name.as_str()), &extra[2..])
    } else {
        (None, &extra[..])
    };

    match rest.first().map(String::as_str) {
        Some("set") => {
            let Some(preset) = rest.get(1) else {
                die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set <default|strict|compute|none|custom>");
            };
            set(ctx, vault, explicit_rootfs, preset, pw)
        }
        Some("edit") => {
            let Some(preset) = rest.get(1) else {
                die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] edit <preset>");
            };
            edit(ctx, vault, explicit_rootfs, preset, pw)
        }
        Some("state") | None => state(ctx, vault, explicit_rootfs),
        _ => die!("usage: cas <vault> settings security sandbox seccomp [--rootfs <name>] set|edit <preset> | state"),
    }
}

fn set(ctx: &Ctx, vault: &Vault, explicit_rootfs: Option<&str>, preset: &str, pw: Option<&str>) -> Result<()> {
    if !registry::seccomp::PRESET_NAMES.contains(&preset) {
        die!("unknown seccomp preset '{preset}' -- expected one of: {}", registry::seccomp::PRESET_NAMES.join(", "));
    }
    let key = target_key(vault, explicit_rootfs)?;
    if preset == "custom" && !custom_file_path(vault, &key).exists() {
        die!("no custom syscall list yet for this target -- run 'seccomp edit custom' first");
    }

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

fn edit(ctx: &Ctx, vault: &Vault, explicit_rootfs: Option<&str>, preset: &str, pw: Option<&str>) -> Result<()> {
    if preset != "custom" {
        die!("built-in presets aren't editable -- use 'seccomp set custom' and 'seccomp edit custom' to define your own allowlist");
    }
    let key = target_key(vault, explicit_rootfs)?;
    let path = custom_file_path(vault, &key);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    if !path.exists() {
        fs::write(&path, "# one syscall name per line\n")?;
    }

    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "vi".to_string());
    let status = std::process::Command::new(&editor).arg(&path).status()?;
    if !status.success() {
        die!("'{editor}' exited with an error -- custom syscall list not updated");
    }

    let contents = fs::read(&path)?;
    let mut hasher = Sha256::new();
    hasher.update(&contents);
    let hash: String = hasher.finalize().iter().map(|b| format!("{b:02x}")).collect();

    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    let mut hashes = meta.sandbox_seccomp_custom_hash.clone().unwrap_or_default();
    hashes.insert(key.clone(), hash);
    meta.sandbox_seccomp_custom_hash = Some(hashes);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;

    logf!(ctx, "[✓] custom syscall list updated for {}", target_label(&key));
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
