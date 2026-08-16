// &desc: "`cas <vault> exec [--rootfs <name>] [-- <cmd>...]` -- drops a shell (or runs one command) inside the sandbox, isolating either a named rootfs environment (base+upper overlay) or the vault's own mount directly as the new root, holding a liveness lock (lockfile.rs) for the session's duration. CLI wiring only; the actual syscall sequence lives in src/sandbox/, which knows nothing about vaults, environments, or the CLI."
pub mod lockfile;

use std::fs;

use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::{is_enabled, namespaces, rootfs};
use crate::ctx::Ctx;
use crate::debugf;
use crate::die;
use crate::error::Result;
use crate::meta::Meta;
use crate::sandbox::{self, namespaces::Flags, overlay};
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    if !vault.is_mount() {
        die!("vault '{}' is closed -- open it first: cas {} open", vault.name, vault.name);
    }

    let meta = Meta::read(&vault.img);
    if !is_enabled(&meta) {
        die!("sandbox is not enabled for '{}' -- run 'cas {} settings security sandbox enable' first", vault.name, vault.name);
    }
    // Verification-gated the same as any other sandbox setting change --
    // exec is a privileged-adjacent action (real code execution against
    // the vault's contents), worth the same bar as toggling the
    // protection that permits it.
    gate_inner(ctx, vault, "sandbox", pw)?;

    let mut i = 0;
    let explicit_rootfs = if extra.first().map(String::as_str) == Some("--rootfs") {
        let Some(name) = extra.get(1) else {
            die!("usage: cas <vault> exec [--rootfs <name>] [-- <cmd>...]\n    --rootfs requires a name");
        };
        i = 2;
        Some(name.as_str())
    } else {
        None
    };

    let mut argv: Vec<String> = match extra.get(i).map(String::as_str) {
        None => Vec::new(),
        Some("--") => extra[i + 1..].to_vec(),
        Some(other) => die!("usage: cas <vault> exec [--rootfs <name>] [-- <cmd>...]\n    unexpected argument: {other}"),
    };
    if argv.is_empty() {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
        argv = vec![shell];
    }

    let active_namespaces = namespaces::active(&meta);
    let flags = Flags {
        mount: active_namespaces.iter().any(|n| n == "mount"),
        pid: active_namespaces.iter().any(|n| n == "pid"),
        uts: active_namespaces.iter().any(|n| n == "uts"),
        ipc: active_namespaces.iter().any(|n| n == "ipc"),
        user: true, // non-negotiable, see namespaces::ALL's doc comment
        net: active_namespaces.iter().any(|n| n == "net"),
    };

    let chosen = rootfs::resolve(vault, explicit_rootfs)?;
    let (new_root, overlay_dirs) = match &chosen {
        Some(name) => {
            let env_dir = vault.rootfs_dir().join(name);
            let merged = env_dir.join("merged");
            fs::create_dir_all(&merged)?;
            let spec = overlay::Spec { lower: env_dir.join("base"), upper: env_dir.join("upper"), work: env_dir.join("work") };
            debugf!(ctx, "exec: using rootfs '{name}' (base={} upper={})", spec.lower.display(), spec.upper.display());
            (merged, Some(spec))
        }
        None => (vault.mnt.clone(), None),
    };

    debugf!(ctx, "exec: namespaces={active_namespaces:?}, argv={argv:?}, new_root={}", new_root.display());
    let old_root_relative = std::path::Path::new(".casket").join("oldroot");

    // Held for the duration of the sandboxed session so `close`/
    // `sandbox disable`/`rootfs remove`/`rootfs rename` can refuse
    // while it's live -- explicitly dropped (not just left to go out of
    // scope) because std::process::exit below skips destructors
    // entirely.
    let lock = lockfile::acquire(vault)?;
    let result = sandbox::run(&new_root, &old_root_relative, &flags, &argv, ctx.debug, overlay_dirs);
    drop(lock);

    let code = result.map_err(|e| crate::error::CasError::new(format!("exec failed: {e}")))?;
    std::process::exit(code);
}

