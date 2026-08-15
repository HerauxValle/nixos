// &desc: "`rootfs update <name> [<version>] | update <name> --tarball <path>` -- replaces base/ only, never upper/, so anything installed/edited inside an environment survives a base refresh. Refuses if the given mode doesn't match how the environment was originally created (.casket-source's 'kind')."
use std::fs;
use std::path::Path;

use crate::commands::exec::lockfile;
use crate::commands::settings::security::sandbox::rootfs::{add, ensure_dir};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::prompt;
use crate::vault::Vault;

enum Source {
    Preset { preset: String },
    Tarball,
}

fn read_source(env_dir: &Path) -> Result<Source> {
    let raw = fs::read_to_string(env_dir.join(".casket-source"))?;
    let value: serde_json::Value = serde_json::from_str(&raw)?;
    match value.get("kind").and_then(|v| v.as_str()) {
        Some("preset") => {
            let preset = value.get("preset").and_then(|v| v.as_str()).unwrap_or_default().to_string();
            Ok(Source::Preset { preset })
        }
        Some("tarball") => Ok(Source::Tarball),
        _ => die!(".casket-source is missing or has an unrecognized 'kind'"),
    }
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String]) -> Result<()> {
    let Some(name) = extra.first() else {
        die!("usage: cas <vault> settings security sandbox rootfs update <name> [<version>] | update <name> --tarball <path>");
    };

    if vault.is_mount() && lockfile::is_live(vault) {
        die!("'{}' has a live 'cas exec' session -- wait for it to exit before updating a rootfs environment", vault.name);
    }

    let env_dir = ensure_dir(vault)?.join(name);
    if !env_dir.exists() {
        die!("rootfs environment '{name}' doesn't exist -- see 'cas <vault> settings security sandbox rootfs list'");
    }
    let source = read_source(&env_dir)?;

    let warning = "this replaces the base filesystem entirely -- anything you've installed or edited (which lives separately, in upper/) is preserved, but base/ itself will be wiped and re-populated";

    let tarball_flag = extra.get(1).map(String::as_str) == Some("--tarball");
    let label = match &source {
        Source::Preset { preset } if tarball_flag => {
            die!("'{name}' was created from a preset ('{preset}') -- update it with 'rootfs update {name} [<version>]', not --tarball");
        }
        Source::Tarball if !tarball_flag => {
            die!("'{name}' was created from a tarball -- update it with 'rootfs update {name} --tarball <path>', not a version");
        }
        Source::Tarball => {
            let Some(path) = extra.get(2) else {
                die!("usage: cas <vault> settings security sandbox rootfs update {name} --tarball <path>");
            };
            if !prompt::confirm_named(ctx, name, "environment", warning)? {
                die!("aborted");
            }
            let base_dir = env_dir.join("base");
            fs::remove_dir_all(&base_dir)?;
            fs::create_dir_all(&base_dir)?;
            add::extract_tarball_into(&base_dir, Path::new(path))?;
            path.clone()
        }
        Source::Preset { preset } => {
            let version = extra.get(1).map(String::as_str);
            if !prompt::confirm_named(ctx, name, "environment", warning)? {
                die!("aborted");
            }
            let base_dir = env_dir.join("base");
            fs::remove_dir_all(&base_dir)?;
            fs::create_dir_all(&base_dir)?;
            let resolved_version = add::fetch_preset_into(ctx, &base_dir, preset, version)?;
            fs::write(env_dir.join(".casket-source"), format!(r#"{{"kind":"preset","preset":"{preset}","version":"{resolved_version}"}}"#))?;
            resolved_version
        }
    };

    let (uid, gid) = crate::udisks::real_user_ids();
    crate::proc::run("chown", &["-R", &format!("{uid}:{gid}"), &env_dir.join("base").to_string_lossy()])?;

    logf!(ctx, "[✓] '{name}' updated ({label})");
    Ok(())
}
