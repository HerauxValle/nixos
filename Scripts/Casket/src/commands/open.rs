// &desc: "`cas <vault> open` — unlock and mount the vault, formatting it on first use and re-applying btrfs label/size housekeeping every time."
use std::path::Path;

use crate::btrfs;
use crate::commands::backup::maybe_auto_backup;
use crate::commands::settings::security::{bruteforce_lockout, ransomware_protection};
use crate::ctx::Ctx;
use crate::debugf;
use crate::error::{CasError, Result};
use crate::header;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::migrations;
use crate::secret::{decode_autokey, get_secret};
use crate::tamper;
use crate::udisks;
use crate::vault::Vault;

/// If `bruteforceLockout` is on, test the passphrase *before* the real
/// unlock attempt so a wrong guess is unambiguous (not confused with an
/// unrelated open failure — a busy mapper looks identical to a bad
/// passphrase from `open_luks`'s error alone). A correct guess resets
/// the counter; a wrong one increments it and, past the threshold,
/// deletes the vault with no confirmation — that's the point of turning
/// this on. Returns `Err` (aborting the open) exactly when it deleted
/// the vault or the passphrase was wrong; `Ok(false)` means proceed.
fn check_lockout(ctx: &Ctx, vault: &Vault, secret: &[u8], meta: &mut Meta) -> Result<bool> {
    if !bruteforce_lockout::is_enabled(meta) {
        return Ok(false);
    }
    Meta::strip(&vault.img)?;
    // Not luks::test -- that only proves anything when the header is
    // still native-front (see header::relocate::verify_current_secret's
    // own doc comment). With headerOffset/headerEncryption on, the front
    // of the file is scrubbed CSPRNG filler, so a plain luks::test always
    // fails regardless of passphrase correctness -- confirmed live to
    // delete a vault using its own correct password before this fix.
    let ok = header::relocate::verify_current_secret(vault, meta, secret);

    // cryptsetup's "No key available with this passphrase" is genuinely
    // ambiguous between "wrong passphrase" and "the keyslot/header data
    // it checked against is corrupted" -- confirmed live: a byte flip
    // from bitrot/a bad sector/a torn write inside the header region
    // reproduces the identical failure as a mistyped passphrase, with
    // the LUKS2 JSON metadata's own checksum still validating fine (the
    // corruption doesn't have to land in the part cryptsetup checksums).
    // Native-front: `native_header_digest` reads the header straight off
    // the file, independent of any passphrase, since the header always
    // lives at a fixed offset. Relocated (headerOffset/headerEncryption):
    // the room-slot address is secret-derived, so the *baseline*'s own
    // slot index (`meta.header_checksum_slot`, pinned down back when the
    // baseline was last seeded with a known-correct secret) is what gets
    // re-checked here -- not a slot re-derived from this attempt's own
    // (possibly wrong) secret, which would map to an unrelated slot and
    // false-flag as "corruption" on every ordinary wrong-passphrase
    // attempt. See `header::relocate::reseed_lockout_baseline`'s doc
    // comment for why the baseline has to be re-seeded at every
    // relocation/encryption/rotation transition too.
    if !ok {
        let corrupted = if header::relocate::is_native_front(meta) {
            let current = luks::native_header_digest(&vault.img);
            matches!((meta.header_checksum.clone(), current), (Some(stored), Some(current)) if stored != current)
        } else if let Some(slot) = meta.header_checksum_slot {
            let current = header::relocate::room_slot_digest(&vault.img, slot);
            matches!((meta.header_checksum.clone(), current), (Some(stored), Some(current)) if stored != current)
        } else {
            false
        };
        if corrupted {
            meta.write(&vault.img)?;
            logf!(ctx, "  [!] '{}' LUKS header region changed since the last confirmed-good open -- this looks like corruption (bitrot, a bad sector, a torn write), not a wrong passphrase", vault.name);
            logf!(ctx, "      not counted toward bruteforceLockout; run 'cas {} tampered' before retrying", vault.name);
            return Err(CasError::Silent);
        }
    }

    if ok {
        if header::relocate::is_native_front(meta) {
            meta.header_checksum = luks::native_header_digest(&vault.img);
            meta.header_checksum_slot = None;
        } else if let Some(slot) = header::relocate::current_room_slot(&vault.img, secret) {
            meta.header_checksum = header::relocate::room_slot_digest(&vault.img, slot);
            meta.header_checksum_slot = Some(slot);
        }
        if meta.failed_attempts.is_some() {
            meta.failed_attempts = None;
        }
        meta.write(&vault.img)?;
        return Ok(false);
    }
    meta.write(&vault.img)?;

    let attempts = meta.failed_attempts.unwrap_or(0) + 1;
    let threshold = bruteforce_lockout::threshold(meta);
    if attempts >= threshold {
        let _ = std::fs::remove_file(&vault.img);
        vault.cleanup_mnt_dir();
        logf!(ctx, "[x] '{}' deleted — {threshold} consecutive wrong-passphrase attempts reached (bruteforceLockout)", vault.name);
        return Err(CasError::Silent);
    }
    meta.failed_attempts = Some(attempts);
    meta.write(&vault.img)?;
    logf!(ctx, "  [!] wrong passphrase ({attempts}/{threshold} — vault deletes at {threshold})");
    Err(CasError::Silent)
}

/// Check the metadata HMAC now that the real secret is known, and if it
/// doesn't match, throw away the protected fields' current values
/// (they're exactly what's suspect) and fall back to the safe setting
/// for each instead — never a silent downgrade. The open still
/// proceeds; refusing to open would risk locking the owner out over a
/// false positive (a migration bug, a hand edit made before this
/// feature existed) with no way back in.
fn check_tamper(ctx: &Ctx, vault: &Vault, secret: &[u8], meta: &mut Meta) {
    // tamper::verify's HMAC is keyed by whatever secret was passed in --
    // an unverified/wrong secret produces a mismatch indistinguishable
    // from real tampering. Previously that false positive only reset
    // cosmetic protection-strength booleans; now that header_offset/
    // header_encryption are also HMAC-covered, reset_to_safe running with
    // a *wrong* secret confirmed-live corrupts those fields (ground_truth
    // can't prove anything with a wrong secret, falls back to
    // native-front, and that bogus value gets persisted even though the
    // open then fails) -- bricking the vault until an accidental
    // self-heal on the next correct attempt. Only run the tamper check
    // once the secret is actually confirmed to unlock this vault; if it
    // doesn't, there's nothing safe to conclude either way, so do nothing
    // and let the real open attempt fail with its normal error instead.
    if !header::relocate::verify_current_secret(vault, meta, secret) {
        return;
    }
    if tamper::verify(secret, meta) == tamper::Status::Tampered {
        logf!(ctx, "  [!] '{}' metadata failed its tamper check — one or more protected settings don't match what was last written with a verified passphrase", vault.name);
        logf!(ctx, "      resetting those settings to their safe values; review with 'cas {} info' and adjust as needed", vault.name);
        tamper::reset_to_safe(&vault.img, secret, meta);
        // The reset values are freshly-verified-legitimate the moment
        // they're written here (we have the real secret in hand right
        // now) — refresh the HMAC baseline to match, or every future
        // `tampered`/`open` would report Tampered forever, even after
        // the exact fix this block just applied.
        tamper::refresh(secret, meta);
    }
}

pub fn run(
    ctx: &Ctx,
    vault: &Vault,
    pw: &str,
    kf_override: Option<&Path>,
    explicit_kf: bool,
    kf_cache_hint: Option<&Path>,
) -> Result<()> {
    if vault.is_mount() {
        logf!(ctx, "[i] '{}' is already open at {}", vault.name, vault.mnt.display());
        return Ok(());
    }
    // Concurrent `open` attempts against the same vault are serialized
    // by `cli.rs`'s `vault.lock_exclusive()` before this function is
    // ever called -- without that, parallel wrong-passphrase guesses
    // race on the LUKS mapper device name (`casvault_<name>`), most/all
    // of them failing with a generic "could not unlock" error from the
    // busy mapper instead of ever reaching `check_lockout`'s counting
    // logic below, which silently defeats `bruteforceLockout` entirely
    // -- confirmed live: 30 genuinely-wrong parallel attempts against
    // threshold=3 left the vault untouched. Do NOT re-lock here: a
    // second `lock_exclusive()` call in the same process opens a second
    // fd on the same lock file and self-deadlocks trying to acquire a
    // `flock` the first fd (held by the caller) already has.
    // clean up a stale mapper left behind by a crashed previous run
    if vault.mapper_dev_exists() {
        vault.close_mapper();
    }
    vault.ensure_mnt_dir()?;

    let (mut meta, schema_from) = Meta::read_versioned(&vault.img);

    // Encryption UX bypass: unlock with the stored autokey, no prompt —
    // this check is unconditional (unlike get_secret's own internal
    // bypass check, which only applies when no keyfile override is
    // given), matching the original's top-level cmd_open branch exactly.
    if meta.is_encryption_bypassed() {
        let secret = decode_autokey(&meta)?;
        check_tamper(ctx, vault, &secret, &mut meta);
        logf!(ctx, "[cas] opening '{}' ...", vault.name);
        return unlock_and_mount(ctx, vault, &secret, &meta, schema_from);
    }

    let (secret, mut new_meta) =
        get_secret(ctx, &vault.img, pw, kf_override, explicit_kf, kf_cache_hint, Some(meta.clone()))?;
    check_lockout(ctx, vault, &secret, &mut new_meta)?;
    check_tamper(ctx, vault, &secret, &mut new_meta);
    let updated_meta = new_meta != meta;
    logf!(ctx, "[cas] opening '{}' ...", vault.name);
    unlock_and_mount(ctx, vault, &secret, &new_meta, schema_from)?;
    if updated_meta {
        logf!(ctx, "  [i] updated cached keyfile path");
    }
    Ok(())
}

/// Open via `luks::open_luks` normally, or via the detached-header path
/// (`luks::open_luks_detached`) if `headerOffset`/`headerEncryption` has
/// moved the header off the container's front — same
/// stale-mapper-vs-bad-passphrase care `open_luks`'s own doc comment
/// describes applies here too: `run()` already cleans up a stale mapper
/// from a crashed previous attempt *before* this is ever reached (see
/// its `vault.mapper_dev_exists()` check), so a failure surfacing here
/// is attributable to the passphrase/header material itself, not a
/// leftover busy mapper being misread as "wrong passphrase". The
/// opportunistic crash-window scrub resume also runs first — if a prior
/// `headerOffset` enable was interrupted mid-scrub, this finishes it
/// before relying on `meta.header_offset` to decide which path to take.
fn open_dispatch(vault: &Vault, meta: &Meta, secret: &[u8]) -> Result<String> {
    header::relocate::resume_scrub_if_pending(&vault.img);

    if header::relocate::is_native_front(meta) {
        return luks::open_luks(&vault.img, &vault.mapper, secret);
    }

    let salt = header::room::read_salt(&vault.img)
        .ok_or_else(|| CasError::new("vault metadata says the header is relocated/encrypted, but no header room was found — vault metadata is inconsistent"))?;
    let master = header::derive_master_secret(&[secret], &salt);
    let staged = header::relocate::stage_current_header(vault, meta, Some(&master))
        .map_err(|e| CasError::new(format!("could not locate the relocated/encrypted header: {e}")))?;
    luks::open_luks_detached(staged.path(), &vault.img, &vault.mapper, secret)
}

/// Strip the trailer, unlock via cryptsetup, restore the trailer
/// (always, even on failure), format on first use, mount, and reconcile
/// btrfs/udisks bookkeeping.
fn unlock_and_mount(ctx: &Ctx, vault: &Vault, secret: &[u8], meta: &Meta, schema_from: u64) -> Result<()> {
    Meta::strip(&vault.img)?;
    let dev = match open_dispatch(vault, meta, secret) {
        Ok(d) => d,
        Err(e) => {
            meta.write(&vault.img)?;
            return Err(e);
        }
    };
    meta.write(&vault.img)?;

    let size_mb = vault.img.metadata()?.len() / (1024 * 1024);
    // The /dev/mapper/<name> symlink `dev` points at is created by udev
    // asynchronously after `cryptsetup open` returns, not synchronously
    // by the ioctl itself -- for a detached-header dm-integrity (+
    // dm-crypt) two-layer activation specifically, that lag is long
    // enough to reliably race `blkid` below and read the device before
    // its content is fully in place, misreporting "no filesystem" and
    // triggering a destructive `mkfs.btrfs` over real data. Confirmed
    // live 2026-08-17. `udevadm settle` blocks until the queue drains,
    // closing the race; a short bounded timeout so a stuck udev queue
    // (unrelated to this device) can't hang `open` indefinitely.
    crate::proc::run_silent("udevadm", &["settle", "--timeout=5"]);
    let blkid = btrfs::blkid_output(&dev);
    debugf!(ctx, "unlock_and_mount: dev={dev} blkid_output={blkid:?}");
    if !blkid.contains("btrfs") {
        logf!(ctx, "  [i] first open — formatting filesystem ...");
        btrfs::mkfs(&dev, &vault.name, size_mb)?;
    }
    vault.mount(&dev)?;

    // Layout migrations need the mounted filesystem, so they can only
    // run here — before anything else (auto-backup, ransomware lock
    // enforcement) touches whatever they're renaming/restructuring.
    debugf!(ctx, "calling migrate_layout with schema_from={schema_from}");
    migrations::migrate_layout(ctx, vault, schema_from);

    logf!(ctx, "  [i] verifying filesystem size ...");
    btrfs::resize_silent(&vault.mnt, "max");
    btrfs::set_label(&vault.mnt, &vault.name, size_mb);
    udisks::udev_retrigger(&dev);

    udisks::chown_to_vault_owner(&vault.mnt, &vault.img)?;
    maybe_auto_backup(ctx, vault, meta);
    ransomware_protection::enforce_on_open(ctx, vault, meta);
    logf!(ctx, "[✓] '{}' is open at {}", vault.name, vault.mnt.display());
    Ok(())
}
