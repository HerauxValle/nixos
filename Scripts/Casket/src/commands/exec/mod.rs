// &desc: "`cas <vault> exec [--rootfs <name>] [-- <cmd>...]` -- drops a shell (or runs one command) inside the sandbox, isolating either a named rootfs environment (base+upper overlay) or the vault's own mount directly as the new root, holding a liveness lock (lockfile.rs) for the session's duration. CLI wiring only; the actual syscall sequence lives in src/sandbox/, which knows nothing about vaults, environments, or the CLI."
pub mod lockfile;

use std::fs;

use sha2::{Digest, Sha256};

use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::{cgroups as cgroup_settings, is_enabled, namespaces, network as network_settings, rootfs, seccomp as seccomp_settings};
use crate::ctx::Ctx;
use crate::debugf;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::registry;
use crate::sandbox::{self, cgroup, namespaces::Flags, overlay, seccomp};
use crate::tamper;
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
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    // tamper.rs's HMAC over sandbox_enabled/namespaces/seccomp is only
    // checkable once the real secret is known (by design -- see
    // tamper.rs's own doc comment) -- which verification just resolved,
    // if it ran. Skipping this check here would mean the *only* place
    // that ever validates the tag for these fields is `open`/`info`/
    // `tampered`, never the command that actually acts on them: a
    // stale-HMAC trailer edit (e.g. `sandbox_namespaces` narrowed, or a
    // seccomp preset weakened) would silently apply at exec time with
    // no warning, even though `info --pass` would correctly flag it.
    if let Some((_, secret)) = &verified {
        if tamper::verify(secret, &meta) == tamper::Status::Tampered {
            die!(
                "sandbox settings for '{}' don't match their integrity tag -- something edited the trailer outside a verified write. Run 'cas {} settings verification state' to inspect, or re-apply sandbox/namespaces/seccomp settings through their normal commands to restore a trusted baseline before running exec",
                vault.name,
                vault.name
            );
        }
    }

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

    let seccomp_filter = resolve_seccomp(ctx, vault, &meta, explicit_rootfs)?;
    let cgroup_handle = resolve_cgroup(ctx, vault, &meta)?;
    let internet = flags.net && network_settings::is_enabled(&meta);
    // Always surfaced, not just when `net` is active -- a vault can have
    // `internet` left "enabled" in its metadata while `net` itself was
    // since removed from `namespaces` (narrowed after the fact); in that
    // state `flags.net` is false, no network namespace gets unshared at
    // all, and the sandboxed process gets the host's real, unrestricted
    // network -- silently, with nothing printed, before this covered
    // every case explicitly (confirmed via pentest review: previously
    // only the `net && !internet` case logged anything).
    if !flags.net {
        logf!(ctx, "  [i] network: unrestricted -- shares the host's real network (namespaces doesn't include 'net')");
    } else if !internet {
        logf!(ctx, "  [i] network: loopback only -- 'settings security sandbox network internet enable' for outbound access");
    } else {
        logf!(ctx, "  [i] network: real outbound connectivity active (veth + host NAT)");
    }
    debugf!(ctx, "exec: namespaces={active_namespaces:?}, argv={argv:?}, new_root={}", new_root.display());
    let old_root_relative = std::path::Path::new(".casket").join("oldroot");

    // Held for the duration of the sandboxed session so `close`/
    // `sandbox disable`/`rootfs remove`/`rootfs rename` can refuse
    // while it's live -- explicitly dropped (not just left to go out of
    // scope) because std::process::exit below skips destructors
    // entirely.
    let lock = lockfile::acquire(vault)?;
    let result = sandbox::run(&new_root, &old_root_relative, &flags, &argv, ctx.debug, overlay_dirs, seccomp_filter, cgroup_handle, internet);
    drop(lock);

    let code = result.map_err(|e| crate::error::CasError::new(format!("exec failed: {e}")))?;
    std::process::exit(code);
}

/// Resolves the configured seccomp setting for this exec target into
/// what `sandbox::run` actually needs. Unset defaults to the "default"
/// preset (a real, if broad, filter); only the "none" preset itself
/// resolves to `Ok(None)`, skipping filtering entirely. Built-ins and
/// named custom profiles share one flat namespace -- checked here in
/// that order, built-in first -- since `profiles::create`/`rename`
/// refuse any name that collides with a built-in, so the two can never
/// actually name the same thing. A custom profile is verified against
/// its stored hash before use; a mismatch (or a missing profile/hash)
/// fails toward the safer "strict" preset instead of silently running
/// unfiltered or on stale rules -- same "fail toward more protective"
/// rule `tamper::reset_to_safe` already uses for this exact field.
fn resolve_seccomp(ctx: &Ctx, vault: &Vault, meta: &Meta, explicit_rootfs: Option<&str>) -> Result<Option<seccomp::Filter>> {
    let key = seccomp_settings::target_key(vault, explicit_rootfs)?;
    let preset = meta.sandbox_seccomp.as_ref().and_then(|m| m.get(&key)).cloned().unwrap_or_else(|| "default".to_string());

    if preset == "none" {
        return Ok(None);
    }

    let presets = registry::seccomp::load();
    let filter = if let Some(entry) = presets.get(&preset) {
        match entry.mode {
            registry::seccomp::Mode::AllowAll => None,
            registry::seccomp::Mode::Denylist => Some(seccomp::Filter { default_deny: false, allow: Vec::new(), deny: entry.syscalls.clone() }),
            registry::seccomp::Mode::Allowlist => Some(seccomp::Filter { default_deny: true, allow: entry.syscalls.clone(), deny: Vec::new() }),
        }
    } else if seccomp_settings::profiles::exists(vault, &preset) {
        let stored_hash = meta.sandbox_seccomp_profile_hash.as_ref().and_then(|m| m.get(&preset));
        let actual_hash = fs::read(seccomp_settings::profiles::path(vault, &preset)).ok().map(|bytes| {
            let mut hasher = Sha256::new();
            hasher.update(&bytes);
            hasher.finalize().iter().map(|b| format!("{b:02x}")).collect::<String>()
        });
        if stored_hash.is_some() && stored_hash == actual_hash.as_ref() {
            match seccomp_settings::profiles::read(vault, &preset) {
                Ok(profile) => Some(profile.to_filter()),
                Err(_) => Some(strict_filter()),
            }
        } else {
            logf!(ctx, "  [!] custom seccomp profile '{preset}' is missing or doesn't match its recorded hash -- falling back to 'strict' rather than running unfiltered or on unverified rules");
            Some(strict_filter())
        }
    } else {
        // Meta holds a name neither the built-in registry nor the
        // vault's own custom profiles know (e.g. a hand-edited trailer,
        // or a profile that's since been deleted) -- same "fail toward
        // more protective" fallback as an unverified custom list.
        logf!(ctx, "  [!] unknown seccomp preset or custom profile '{preset}' in metadata -- falling back to 'strict'");
        Some(strict_filter())
    };

    if let Some(f) = &filter {
        warn_unresolvable_syscalls(ctx, &preset, f);
    }
    Ok(filter)
}

/// `sandbox::seccomp::apply` silently skips any syscall name that
/// doesn't resolve on the host's own architecture table -- correct
/// behavior for genuinely arch-specific names, but silent either way,
/// so a filter that's fully correct on x86_64 could quietly end up
/// weaker than intended on aarch64 (or vice versa) with no signal ever
/// reaching the user. This surfaces that gap at the one point it
/// actually matters -- right before the filter built here is handed to
/// `sandbox::run`, on whichever architecture `cas` is actually running
/// on right now.
fn warn_unresolvable_syscalls(ctx: &Ctx, preset: &str, filter: &seccomp::Filter) {
    let names = unresolvable_syscalls(&filter.allow, &filter.deny);
    if !names.is_empty() {
        logf!(
            ctx,
            "  [!] '{preset}' lists syscalls that don't resolve on this architecture ({}): {} -- they're silently skipped, not enforced, so this filter is weaker here than it looks",
            std::env::consts::ARCH,
            names.join(", ")
        );
    }
}

/// Pure lookup, split out from `warn_unresolvable_syscalls` so it's
/// testable without a `Ctx` -- every name across both lists that isn't
/// in the host's own architecture table. Empty if the host's
/// architecture has no table at all (`apply()` itself already refuses
/// cleanly in that case, nothing more to say here).
fn unresolvable_syscalls(allow: &[String], deny: &[String]) -> Vec<String> {
    let Some(table) = crate::sandbox::syscall_table::for_host_arch() else {
        return Vec::new();
    };
    allow.iter().chain(deny.iter()).filter(|s| !table.contains_key(s.as_str())).cloned().collect()
}

#[cfg(test)]
mod tests {
    use super::unresolvable_syscalls;

    #[test]
    fn flags_names_missing_from_the_host_syscall_table() {
        let allow = vec!["read".to_string(), "totally_fake_syscall_xyz".to_string()];
        let deny = vec!["mount".to_string()];
        let bad = unresolvable_syscalls(&allow, &deny);
        assert_eq!(bad, vec!["totally_fake_syscall_xyz".to_string()]);
    }

    #[test]
    fn empty_when_everything_resolves() {
        let allow = vec!["read".to_string(), "write".to_string(), "getpid".to_string()];
        let deny = vec!["mount".to_string(), "ptrace".to_string()];
        assert!(unresolvable_syscalls(&allow, &deny).is_empty());
    }
}

/// Prepares this session's cgroup, if the vault has any limits
/// configured -- `None` (no cgroup, no resource ceiling) when
/// `cgroups::active` returns an empty `Spec`, matching the "unset means
/// unlimited" default the settings side already documents. Fails loudly
/// (rather than silently running unlimited) if limits *are* configured
/// but the host can't actually enforce them -- a user who explicitly
/// asked for a memory cap should never get a session that quietly
/// ignores it.
fn resolve_cgroup(ctx: &Ctx, vault: &Vault, meta: &Meta) -> Result<Option<cgroup::Handle>> {
    let spec = cgroup_settings::active(meta);
    if spec.is_empty() {
        return Ok(None);
    }
    let session = format!("{}-{}", vault.name.replace(|c: char| !c.is_alphanumeric(), "_"), std::process::id());
    let handle = cgroup::prepare(&session, &spec).map_err(|e| crate::error::CasError::new(format!("failed to apply configured cgroup limits: {e}")))?;
    debugf!(ctx, "exec: cgroup session '{session}' prepared");
    Ok(Some(handle))
}

fn strict_filter() -> seccomp::Filter {
    let presets = registry::seccomp::load();
    seccomp::Filter { default_deny: true, allow: presets["strict"].syscalls.clone(), deny: Vec::new() }
}

