// &desc: "`cas <vault> exec [--rootfs <name>] [-- <cmd>...]` -- drops a shell (or runs one command) inside the sandbox namespaces isolate the vault's own mount as the new root. CLI wiring only; the actual syscall sequence lives in src/sandbox/, which knows nothing about vaults or the CLI. --rootfs is parsed but rejected until named rootfs environments exist (later slice)."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::{is_enabled, namespaces};
use crate::ctx::Ctx;
use crate::debugf;
use crate::die;
use crate::error::Result;
use crate::meta::Meta;
use crate::sandbox::{self, namespaces::Flags};
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

    let mut argv: Vec<String> = match extra.first().map(String::as_str) {
        None => Vec::new(),
        Some("--rootfs") => die!("usage: cas <vault> exec [-- <cmd>...] -- --rootfs isn't implemented yet"),
        Some("--") => extra[1..].to_vec(),
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

    debugf!(ctx, "exec: namespaces={active_namespaces:?}, argv={argv:?}, new_root={}", vault.mnt.display());
    let old_root_relative = std::path::Path::new(".casket").join("oldroot");
    let code = sandbox::run(&vault.mnt, &old_root_relative, &flags, &argv, ctx.debug)
        .map_err(|e| crate::error::CasError::new(format!("exec failed: {e}")))?;

    std::process::exit(code);
}
