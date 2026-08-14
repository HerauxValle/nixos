// &desc: "`cas <vault> settings security bruteforceLockout enable [--threshold N] | disable | threshold <N> | state` — deletes the vault after too many consecutive wrong-passphrase `open` attempts. Off by default and irreversible when it triggers, so enabling it prints a loud one-time warning. Not a plain enable/disable Feature (`threshold <N>` is a third verb with its own argument), so it's dispatched directly by settings/mod.rs rather than through registry::dispatch, same as backup_auto."
use crate::commands::settings::gate::{gate, gate_inner};
use crate::commands::settings::registry::{self, Feature};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

pub const DEFAULT_THRESHOLD: u32 = 10;

/// Kept for `info`'s rollup, which walks `security::FEATURES` generically
/// for display only — `set` here is never reached through normal
/// dispatch (settings/mod.rs routes "bruteforceLockout" to `dispatch`
/// below before it would ever hit `registry::dispatch`).
pub const FEATURE: Feature = Feature {
    name: "bruteforceLockout",
    set: |ctx, vault, enable, pw| dispatch(ctx, vault, &[if enable { "enable" } else { "disable" }.to_string()], pw),
    get: is_enabled,
};

pub fn is_enabled(meta: &Meta) -> bool {
    meta.bruteforce_lockout == Some(true)
}

pub fn threshold(meta: &Meta) -> u32 {
    meta.bruteforce_threshold.unwrap_or(DEFAULT_THRESHOLD)
}

/// Digits-only *and* fits in `u32` — `s.parse::<u32>()` is the actual
/// validation; a purely digit-based check let a value like
/// `999999999999999999999` pass as "valid" and then panic on the
/// `.unwrap()` every call site used to do right after.
fn parse_threshold(s: &str) -> Option<u32> {
    let n: u32 = s.parse().ok()?;
    (n >= 1).then_some(n)
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => {
            let mut n = None;
            if extra.get(1).map(String::as_str) == Some("--threshold") {
                let Some(parsed) = extra.get(2).and_then(|s| parse_threshold(s)) else {
                    die!("usage: cas <vault> settings security bruteforceLockout enable [--threshold N]\n    N must be a positive whole number");
                };
                n = Some(parsed);
            }
            enable(ctx, vault, n, pw)
        }
        Some("disable") => {
            let verified = gate_inner(ctx, vault, "bruteforceLockout", pw)?;
            let mut meta = Meta::read(&vault.img);
            meta.bruteforce_lockout = None;
            if let Some((_, secret)) = &verified {
                tamper::refresh(secret, &mut meta);
            }
            meta.write(&vault.img)?;
            logf!(ctx, "[✓] bruteforce lockout disabled for '{}'", vault.name);
            Ok(())
        }
        Some("threshold") => {
            let Some(n) = extra.get(1).and_then(|s| parse_threshold(s)) else {
                die!("usage: cas <vault> settings security bruteforceLockout threshold <N>\n    N must be a positive whole number");
            };
            set_threshold(ctx, vault, n, pw)
        }
        Some("state") => {
            let meta = Meta::read(&vault.img);
            let width = registry::column_width(&["bruteforceLockout", "threshold"]);
            logf!(ctx, "{}", registry::line("bruteforceLockout", is_enabled(&meta), width));
            logf!(ctx, "  {}", registry::kv_line("threshold", &threshold(&meta).to_string(), width.saturating_sub(2)));
            Ok(())
        }
        _ => die!("usage: cas <vault> settings security bruteforceLockout enable [--threshold N] | disable | threshold <N> | state"),
    }
}

fn enable(ctx: &Ctx, vault: &Vault, n: Option<u32>, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "bruteforceLockout", pw)?;

    let mut meta = Meta::read(&vault.img);
    meta.bruteforce_lockout = Some(true);
    meta.failed_attempts = None;
    if let Some(n) = n {
        meta.bruteforce_threshold = Some(n);
    }
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;

    let n = threshold(&meta);
    logf!(ctx, "[✓] bruteforce lockout enabled for '{}'", vault.name);
    logf!(ctx, "  [!] after {n} consecutive wrong-passphrase 'open' attempts, this vault gets PERMANENTLY DELETED — no confirmation prompt, no undo");
    logf!(ctx, "      a mistyped passphrase counts the same as an attacker's guess; make sure you're confident before leaving this on");
    Ok(())
}

fn set_threshold(ctx: &Ctx, vault: &Vault, n: u32, pw: Option<&str>) -> Result<()> {
    gate(ctx, vault, "bruteforceLockout", pw)?;

    let mut meta = Meta::read(&vault.img);
    if !is_enabled(&meta) {
        die!("bruteforce lockout is not enabled — run 'cas {} settings security bruteforceLockout enable' first", vault.name);
    }
    meta.bruteforce_threshold = Some(n);
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] bruteforce lockout threshold set to {n} for '{}'", vault.name);
    Ok(())
}
