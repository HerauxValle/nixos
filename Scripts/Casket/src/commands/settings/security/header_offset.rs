// &desc: "`cas <vault> settings security headerOffset enable [--slots N] | disable | slots <N> | state` — relocates the vault's LUKS2 header from the container's front to a passphrase-derived slot inside a header-hiding room (see header/relocate.rs), so a magic-byte scan of the front no longer finds it. On a fileIntegrity vault this stores the real header verbatim (a bigger, `--slots`-sized v3 room) instead of a minimized one, since rebuilding the header would corrupt an integrity-protected payload. Direct-dispatch (not registry::Feature) since enable prints a conditional headerEncryption notice and takes `--slots`, following fileIntegrity.rs's/bruteforce_lockout.rs's pattern."
use crate::commands::settings::gate::gate_pw;
use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::header::relocate;
use crate::header::room;
use crate::logf;
use crate::meta::Meta;
use crate::secret::{combined_secret, resolve_keyfile};
use crate::vault::Vault;

pub fn is_enabled(meta: &Meta) -> bool {
    relocate::offset_enabled(meta)
}

fn parse_slots(s: &str) -> Option<u32> {
    let n: u32 = s.parse().ok()?;
    (n >= 1).then_some(n)
}

/// Prints the one-time "more slots buys no security" note when `n`
/// crosses `room::INTEGRITY_SLOTS_ADVISORY_THRESHOLD` -- see
/// `header::room`'s v3 doc comment for the full reasoning. Never blocks.
fn maybe_advise_on_slots(ctx: &Ctx, n: u32) {
    if n > room::INTEGRITY_SLOTS_ADVISORY_THRESHOLD {
        logf!(ctx, "  [i] {n} slots reserves ~{} MiB just for header hiding -- past a handful, more slots don't add security", n as u64 * room::INTEGRITY_SLOT_SIZE / (1024 * 1024));
        logf!(ctx, "      (each candidate slot costs disk space, not brute-force resistance -- an attacker checks exactly one slot per passphrase guess regardless of how many exist)");
    }
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("enable") => {
            let mut slots = None;
            if extra.get(1).map(String::as_str) == Some("--slots") {
                let Some(parsed) = extra.get(2).and_then(|s| parse_slots(s)) else {
                    die!("usage: cas <vault> settings security headerOffset enable [--slots N]\n    N must be a positive whole number");
                };
                slots = Some(parsed);
            }
            run(ctx, vault, true, pw, slots)
        }
        Some("disable") => run(ctx, vault, false, pw, None),
        Some("slots") => {
            let Some(n) = extra.get(1).and_then(|s| parse_slots(s)) else {
                die!("usage: cas <vault> settings security headerOffset slots <N>\n    N must be a positive whole number");
            };
            change_slots(ctx, vault, n, pw)
        }
        Some("state") => {
            relocate::resume_scrub_if_pending(&vault.img);
            let meta = Meta::read(&vault.img);
            logf!(ctx, "{}", crate::commands::settings::registry::line("headerOffset", is_enabled(&meta), crate::commands::settings::registry::column_width(&["headerOffset"])));
            if let Some(n) = meta.header_room_slots {
                logf!(ctx, "    slots: {n} (fileIntegrity-compatible room)");
            }
            Ok(())
        }
        _ => die!("usage: cas <vault> settings security headerOffset enable [--slots N] | disable | slots <N> | state"),
    }
}

fn resolve_secret(ctx: &Ctx, vault: &Vault, meta: &Meta, pw: &str) -> Result<Vec<u8>> {
    match meta.keyfile.clone() {
        Some(cached) => {
            let mut m = meta.clone();
            let kf_path = resolve_keyfile(ctx, &cached, &mut m, &vault.img)?;
            Ok(combined_secret(pw, &crate::keyfile::read_bytes(&kf_path)?))
        }
        None => Ok(pw.as_bytes().to_vec()),
    }
}

fn run(ctx: &Ctx, vault: &Vault, enable: bool, pw: Option<&str>, slots: Option<u32>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault must be closed first:  cas {} close", vault.name);
    }

    relocate::resume_scrub_if_pending(&vault.img);

    let meta_before = Meta::read(&vault.img);
    if is_enabled(&meta_before) == enable {
        let word = if enable { "enabled" } else { "disabled" };
        die!("headerOffset is already {word} for '{}'", vault.name);
    }
    if let Some(n) = slots {
        maybe_advise_on_slots(ctx, n);
    }

    let pw = gate_pw(ctx, vault, "headerOffset", pw)?;
    let secret = resolve_secret(ctx, vault, &meta_before, &pw)?;
    if !relocate::verify_current_secret(vault, &meta_before, &secret) {
        die!("wrong passphrase — could not verify vault");
    }

    let mut meta = meta_before;
    if enable {
        if let Some(n) = slots {
            meta.header_room_slots = Some(n);
        }
    }
    logf!(ctx, "[cas] {} headerOffset for '{}' ...", if enable { "enabling" } else { "disabling" }, vault.name);

    if enable {
        relocate::enable_offset(ctx, vault, &mut meta, &secret, Strength::default())?;
        logf!(ctx, "[✓] headerOffset enabled for '{}'", vault.name);
        if let Some(n) = meta.header_room_slots {
            logf!(ctx, "    fileIntegrity is on -- stored the real header verbatim in a {n}-slot room");
        }
        if !relocate::encryption_enabled(&meta) {
            logf!(ctx, "  [i] the relocated header's content is not encrypted (headerEncryption is off) — position alone is now hidden, content is still a plain, parseable LUKS2 header to anyone who finds the slot");
            logf!(ctx, "      cas {} settings security headerEncryption enable", vault.name);
        }
    } else {
        relocate::disable_offset(ctx, vault, &mut meta, &secret, Strength::default())?;
        logf!(ctx, "[✓] headerOffset disabled for '{}'", vault.name);
    }
    Ok(())
}

fn change_slots(ctx: &Ctx, vault: &Vault, n: u32, pw: Option<&str>) -> Result<()> {
    if !vault.img.exists() {
        die!("vault '{}' not found", vault.name);
    }
    if vault.is_mount() {
        die!("vault must be closed first:  cas {} close", vault.name);
    }
    let meta_before = Meta::read(&vault.img);
    if !is_enabled(&meta_before) {
        die!("headerOffset is not enabled for '{}'", vault.name);
    }
    if meta_before.header_room_slots.is_none() {
        die!("'{}' isn't using a fileIntegrity-compatible room -- slot count only applies there", vault.name);
    }
    maybe_advise_on_slots(ctx, n);

    let pw = gate_pw(ctx, vault, "headerOffset", pw)?;
    let secret = resolve_secret(ctx, vault, &meta_before, &pw)?;
    if !relocate::verify_current_secret(vault, &meta_before, &secret) {
        die!("wrong passphrase — could not verify vault");
    }

    let mut meta = meta_before;
    logf!(ctx, "[cas] changing headerOffset slot count for '{}' ...", vault.name);
    relocate::change_slot_count(ctx, vault, &mut meta, &secret, n)?;
    logf!(ctx, "[✓] headerOffset now using {n} slots for '{}'", vault.name);
    Ok(())
}
