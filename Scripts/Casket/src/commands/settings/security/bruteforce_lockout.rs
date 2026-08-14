// &desc: "`cas <vault> settings security bruteforceLockout enable|disable` — deletes the vault after too many consecutive wrong-passphrase `open` attempts. Off by default and irreversible when it triggers, so enabling it prints a loud one-time warning."
use crate::commands::settings::gate::gate;
use crate::commands::settings::registry::Feature;
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::vault::Vault;

pub const DEFAULT_THRESHOLD: u32 = 10;

pub const FEATURE: Feature = Feature {
    name: "bruteforceLockout",
    set,
    get: is_enabled,
};

pub fn is_enabled(meta: &Meta) -> bool {
    meta.bruteforce_lockout == Some(true)
}

pub fn threshold(meta: &Meta) -> u32 {
    meta.bruteforce_threshold.unwrap_or(DEFAULT_THRESHOLD)
}

fn set(ctx: &Ctx, vault: &Vault, enable: bool, pw: Option<&str>) -> Result<()> {
    gate(ctx, vault, "bruteforceLockout", pw)?;

    let mut meta = Meta::read(&vault.img);
    meta.bruteforce_lockout = enable.then_some(true);
    if enable {
        meta.failed_attempts = None;
    }
    meta.write(&vault.img)?;

    if enable {
        let n = threshold(&meta);
        logf!(ctx, "[✓] bruteforce lockout enabled for '{}'", vault.name);
        logf!(ctx, "  [!] after {n} consecutive wrong-passphrase 'open' attempts, this vault gets PERMANENTLY DELETED — no confirmation prompt, no undo");
        logf!(ctx, "      a mistyped passphrase counts the same as an attacker's guess; make sure you're confident before leaving this on");
    } else {
        logf!(ctx, "[✓] bruteforce lockout disabled for '{}'", vault.name);
    }
    Ok(())
}
