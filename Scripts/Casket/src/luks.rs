// &desc: "cryptsetup wrappers: open/close a vault, enumerate/add/remove LUKS key slots, and the safe two-phase slot_cycle passphrase rotation."
use std::collections::HashSet;
use std::path::Path;

use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::logf;
use crate::proc::{self, TempKeyfile, TempOutPath};

/// Format a freshly truncated image file as LUKS2 with the given KDF
/// cost preset. The secret goes over stdin, same as every other
/// cryptsetup call here — it never touches disk.
/// `integrity` optionally adds `--integrity hmac-sha256` —
/// per-sector authenticated encryption, used by `create --integrity` and
/// `fileIntegrity`'s migration to build the destination container.
pub fn format_vault_ex(img: &Path, secret: &[u8], strength: Strength, integrity: bool) -> Result<()> {
    let img_str = img.to_string_lossy().into_owned();
    let mut args: Vec<&str> = vec!["luksFormat", "--batch-mode", "--pbkdf", "argon2id"];
    args.extend_from_slice(strength.pbkdf_args());
    args.push("--pbkdf-force-iterations");
    args.push(strength.iterations());
    if integrity {
        args.push("--integrity");
        args.push("hmac-sha256");
    }
    args.push(&img_str);
    args.push("--key-file");
    args.push("-");
    proc::run_with_stdin("cryptsetup", &args, secret)
}

/// Whether an already-formatted container at `img` has integrity
/// protection active, checked against the real on-disk structure (not
/// any metadata flag) via `cryptsetup luksDump` — the ground truth
/// `tamper::reset_to_safe` uses for `Meta.file_integrity`, since that
/// field only describes the container and can't itself change it.
pub fn has_integrity(img: &Path) -> bool {
    let img_str = img.to_string_lossy().into_owned();
    let out = proc::capture("cryptsetup", &["luksDump", &img_str]);
    String::from_utf8_lossy(&out.stdout).to_lowercase().contains("integrity:")
}

pub fn open_luks(img: &Path, mapper: &str, secret: &[u8]) -> Result<String> {
    let img_str = img.to_string_lossy().into_owned();
    // Report cryptsetup's real failure reason instead of a blanket
    // "wrong passphrase" guess — a stale/stuck mapper left behind by a
    // crashed previous run ("Device X already exists") or a device gone
    // busy look identical to a bad passphrase otherwise, and silently
    // relabeling every such failure as a credentials problem sent
    // someone chasing the wrong fix (confirmed live 2026-08-13: a
    // leftover errored mapper from an interrupted run was masked as
    // "wrong passphrase or keyfile" for the rest of the session).
    proc::run_with_stdin("cryptsetup", &["open", "--key-file", "-", &img_str, mapper], secret)
        .map_err(|e| CasError::new(format!("could not unlock vault: {e}")))?;
    Ok(format!("/dev/mapper/{mapper}"))
}

/// Active LUKS key slot numbers, parsed from `cryptsetup luksDump`.
/// Handles both LUKS2 ("  0: luks2") and LUKS1 ("Key Slot 0: ENABLED")
/// dump formats.
fn used_slots(img: &Path) -> HashSet<u32> {
    let img_str = img.to_string_lossy().into_owned();
    let out = proc::capture("cryptsetup", &["luksDump", &img_str]);
    let text = String::from_utf8_lossy(&out.stdout);
    let mut used = HashSet::new();

    for line in text.lines() {
        let trimmed = line.trim_start();
        let lower = trimmed.to_ascii_lowercase(); // ASCII-only: byte offsets stay valid in `trimmed`

        if let Some(colon) = trimmed.find(':') {
            let (num_part, rest) = trimmed.split_at(colon);
            let is_slot_num = !num_part.is_empty() && num_part.bytes().all(|b| b.is_ascii_digit());
            let word = rest[1..].trim_start().split_whitespace().next().unwrap_or("");
            let is_active = matches!(word.to_ascii_lowercase().as_str(), "luks2" | "enabled");
            if is_slot_num && is_active {
                if let Ok(n) = num_part.parse::<u32>() {
                    used.insert(n);
                }
            }
        }

        if let Some(rest_lower) = lower.strip_prefix("key slot") {
            let offset = trimmed.len() - rest_lower.len();
            let rest = trimmed[offset..].trim_start();
            if let Some(colon) = rest.find(':') {
                let (num_part, after) = rest.split_at(colon);
                if let Ok(n) = num_part.trim().parse::<u32>() {
                    if after[1..].trim().eq_ignore_ascii_case("ENABLED") {
                        used.insert(n);
                    }
                }
            }
        }
    }
    used
}

/// Return the slot number `secret` unlocks, by testing each active slot.
pub fn find_used_slot(img: &Path, secret: &[u8]) -> Option<u32> {
    let img_str = img.to_string_lossy().into_owned();
    let mut slots: Vec<u32> = used_slots(img).into_iter().collect();
    slots.sort_unstable();
    for slot in slots {
        let slot_str = slot.to_string();
        let args = ["open", "--test-passphrase", "--key-slot", &slot_str, "--key-file", "-", &img_str];
        if proc::run_with_stdin_status("cryptsetup", &args, secret) {
            return Some(slot);
        }
    }
    None
}

/// First unused slot number (0..32), optionally excluding one.
pub fn find_free_slot(img: &Path, exclude: Option<u32>) -> Option<u32> {
    let used = used_slots(img);
    (0..32).find(|s| !used.contains(s) && Some(*s) != exclude)
}

/// Number of active key slots, for `cas info`. The Python original
/// counted occurrences of the literal string "ENABLED" in `luksDump`
/// output — a LUKS1-only marker that never appears in a LUKS2 dump (this
/// tool always formats LUKS2), so it silently reported 0 for every real
/// vault. This reuses the same slot parser `find_used_slot`/
/// `find_free_slot` rely on, which handles both formats.
pub fn slot_count(img: &Path) -> usize {
    used_slots(img).len()
}

pub fn add_key(img: &Path, auth_secret: &[u8], new_secret: &[u8], strength: Option<Strength>, slot: Option<u32>) -> Result<()> {
    let tf_auth = TempKeyfile::write(auth_secret)?;
    let tf_new = TempKeyfile::write(new_secret)?;
    let img_str = img.to_string_lossy().into_owned();
    let auth_str = tf_auth.path().to_string_lossy().into_owned();
    let new_str = tf_new.path().to_string_lossy().into_owned();
    let slot_str = slot.map(|s| s.to_string());

    let mut args: Vec<&str> = vec!["luksAddKey", "--batch-mode", "--key-file", &auth_str];
    if let Some(s) = strength {
        args.push("--pbkdf");
        args.push("argon2id");
        args.extend_from_slice(s.pbkdf_args());
        args.push("--pbkdf-force-iterations");
        args.push(s.iterations());
    }
    if let Some(ref ss) = slot_str {
        args.push("--key-slot");
        args.push(ss);
    }
    args.push(&img_str);
    args.push(&new_str);

    proc::run("cryptsetup", &args)
}

/// Remove a LUKS slot by number. `auth_secret` must be a valid key for a
/// *different* slot — cryptsetup won't let you kill the slot you're
/// authenticating with.
pub fn remove_slot(img: &Path, slot: u32, auth_secret: &[u8]) -> Result<()> {
    let img_str = img.to_string_lossy().into_owned();
    let slot_str = slot.to_string();
    proc::run_with_stdin(
        "cryptsetup",
        &["luksKillSlot", "--batch-mode", "--key-file", "-", &img_str, &slot_str],
        auth_secret,
    )
}

/// `cryptsetup resize` — grow to the device's full backing size (no
/// `sectors`), or to an exact 512-byte sector count for a shrink.
pub fn resize(mapper: &str, secret: &[u8], sectors: Option<u64>) -> Result<()> {
    match sectors {
        Some(n) => {
            let n_str = n.to_string();
            proc::run_with_stdin("cryptsetup", &["resize", "--key-file", "-", "--size", &n_str, mapper], secret)
        }
        None => proc::run_with_stdin("cryptsetup", &["resize", "--key-file", "-", mapper], secret),
    }
}

// --- headerOffset support: detached-header open/test, volume-key
// extraction, and minimized single-keyslot header formatting. LUKS2
// decouples "where the header lives" from "where the payload data
// offset points" -- a header of any size can describe a payload that
// starts anywhere in a *different* file/device, which is what makes
// header relocation possible without ever touching (or even reading)
// the multi-GB payload itself. Proven live 2026-08-16 against a scratch
// vault: copying just the front 16 MiB into a separate file and
// `--header`-opening from that copy alone (real device untouched)
// mounts and reads back identically to a normal open -- see
// header/relocate.rs for the orchestration that uses these.

/// Detached-header equivalent of `open_luks` -- `img` is always the real
/// `.img` (the payload is never moved, only the header lives elsewhere).
pub fn open_luks_detached(header: &Path, img: &Path, mapper: &str, secret: &[u8]) -> Result<String> {
    let header_str = header.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();
    proc::run_with_stdin(
        "cryptsetup",
        &["open", "--header", &header_str, "--key-file", "-", &img_str, mapper],
        secret,
    )
    .map_err(|e| CasError::new(format!("could not unlock vault: {e}")))?;
    Ok(format!("/dev/mapper/{mapper}"))
}

/// Detached-header equivalent of `test` -- structural-only check (the
/// header's own KDF/passphrase match), same caveat as `test`: proves the
/// header decrypts, not that the payload it points at is the *right*
/// payload. Callers relocating a header for real (`relocate.rs`) verify
/// payload content too, not just this.
pub fn test_detached(header: &Path, img: &Path, secret: &[u8]) -> bool {
    let header_str = header.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();
    proc::run_with_stdin_status(
        "cryptsetup",
        &["open", "--header", &header_str, "--test-passphrase", "--key-file", "-", &img_str],
        secret,
    )
}

/// Byte offset (from the container start) where payload data begins,
/// parsed from `luksDump`'s `offset: N [bytes]` line under "Data
/// segments". `None` if it can't be found/parsed -- callers must treat
/// that as "don't proceed", never guess a default.
pub fn data_offset_bytes(img: &Path) -> Option<u64> {
    let img_str = img.to_string_lossy().into_owned();
    let out = proc::capture("cryptsetup", &["luksDump", &img_str]);
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("offset:") {
            let digits: String = rest.trim().chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(n) = digits.parse::<u64>() {
                return Some(n);
            }
        }
    }
    None
}

/// Sector size (bytes) of the container's data segment, parsed from
/// `luksDump`'s `sector: N [bytes]` line -- critical to get right when
/// forcing a volume key into a brand-new header: XTS's IV is derived
/// from the *sector number*, which depends on this value, so a
/// mismatched sector size between the original container and a
/// replacement/minimized header decrypts the exact same ciphertext
/// bytes to different plaintext even with the identical volume key
/// (confirmed live 2026-08-16 — a real vault created with cryptsetup
/// 2.8.6's modern 4096-byte default, replayed through a minimized
/// header built without `--sector-size` and getting cryptsetup's
/// separate `--header`-mode default of 512, produced a structurally
/// valid open that silently decrypted to garbage). `None` if it can't
/// be parsed -- callers must treat that as "don't proceed", same as
/// `data_offset_bytes`.
pub fn sector_size_bytes(img: &Path) -> Option<u64> {
    let img_str = img.to_string_lossy().into_owned();
    let out = proc::capture("cryptsetup", &["luksDump", &img_str]);
    parse_sector_size(&String::from_utf8_lossy(&out.stdout))
}

/// Detached-header equivalent of `sector_size_bytes` -- `cryptsetup
/// luksDump --header <path>` still requires a `<device>` positional
/// argument even in detached mode (confirmed live 2026-08-17: it
/// refuses with "requires <device> as arguments" otherwise), so `img`
/// is required here too, unlike this function's original doc comment
/// assumed.
pub fn sector_size_bytes_from_header(header: &Path, img: &Path) -> Option<u64> {
    let header_str = header.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();
    let out = proc::capture("cryptsetup", &["luksDump", "--header", &header_str, &img_str]);
    parse_sector_size(&String::from_utf8_lossy(&out.stdout))
}

fn parse_sector_size(text: &str) -> Option<u64> {
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("sector:") {
            let digits: String = rest.trim().chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(n) = digits.parse::<u64>() {
                return Some(n);
            }
        }
    }
    None
}

/// Detached-header equivalent of `data_offset_bytes` -- reads the data
/// offset from a header file. `img` is still required as the positional
/// `<device>` argument (`luksDump --header` alone refuses with
/// "requires <device> as arguments"), even though the offset value
/// itself comes entirely from the header file's own metadata.
pub fn data_offset_bytes_from_header(header: &Path, img: &Path) -> Option<u64> {
    let header_str = header.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();
    let out = proc::capture("cryptsetup", &["luksDump", "--header", &header_str, &img_str]);
    let text = String::from_utf8_lossy(&out.stdout);
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("offset:") {
            let digits: String = rest.trim().chars().take_while(|c| c.is_ascii_digit()).collect();
            if let Ok(n) = digits.parse::<u64>() {
                return Some(n);
            }
        }
    }
    None
}

/// Extract the container's raw volume (master) key into a fresh,
/// caller-owned temp file (mode 0600, deleted on drop) -- needed to
/// format a brand-new minimized detached header that still decrypts the
/// *existing* payload, since a plain `luksFormat` always mints a fresh
/// random volume key otherwise. `secret` must already be a verified key
/// for the container (this doesn't re-verify).
pub fn dump_volume_key(img: &Path, secret: &[u8]) -> Result<TempOutPath> {
    let out = TempOutPath::reserve("vk")?;
    let img_str = img.to_string_lossy().into_owned();
    let out_str = out.path().to_string_lossy().into_owned();
    let _umask = proc::UmaskGuard::scoped_0077();
    proc::run_with_stdin(
        "cryptsetup",
        &["luksDump", "--dump-master-key", "--batch-mode", "--master-key-file", &out_str, "--key-file", "-", &img_str],
        secret,
    )?;
    Ok(out)
}

/// Format a brand-new, minimized single-keyslot LUKS2 header at
/// `header_out` (a plain file, not `img` itself) that decrypts `img`'s
/// *existing* payload starting at `offset_bytes` -- by forcing the same
/// volume key (`volume_key_file`, from `dump_volume_key`) instead of
/// letting `luksFormat` mint a fresh one. `--luks2-keyslots-size 252k`
/// is the measured (not guessed) minimum 4k-aligned keyslots area that
/// still fits one real Argon2id keyslot at cryptsetup 2.8.6 -- see
/// `header::room::SLOT_SIZE`'s doc comment for the full measurement.
/// Never touches `img` beyond reading its existing bytes elsewhere
/// (this call writes only to `header_out`).
pub fn format_minimized_detached_header(
    header_out: &Path,
    img: &Path,
    new_secret: &[u8],
    volume_key_file: &Path,
    offset_bytes: u64,
    sector_size: u64,
    strength: Strength,
) -> Result<()> {
    if offset_bytes % 512 != 0 {
        return Err(CasError::new("data offset is not sector-aligned"));
    }
    let offset_sectors = (offset_bytes / 512).to_string();
    let sector_size_str = sector_size.to_string();
    let header_str = header_out.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();
    let vk_str = volume_key_file.to_string_lossy().into_owned();

    let mut args: Vec<&str> = vec![
        "luksFormat", "--batch-mode", "--type", "luks2",
        "--header", &header_str,
        "--luks2-metadata-size", "16k",
        "--luks2-keyslots-size", "252k",
        "--offset", &offset_sectors,
        // Must match the original container's sector size exactly —
        // XTS's IV is derived from the sector number, so a mismatch
        // here decrypts the same ciphertext bytes to different
        // plaintext even with the correct volume key. See this
        // function's doc comment / `sector_size_bytes`'s for the live
        // bug this fixes.
        "--sector-size", &sector_size_str,
        "--volume-key-file", &vk_str,
        "--pbkdf", "argon2id",
    ];
    args.extend_from_slice(strength.pbkdf_args());
    args.push("--pbkdf-force-iterations");
    args.push(strength.iterations());
    args.push(&img_str);
    args.push("--key-file");
    args.push("-");

    proc::run_with_stdin("cryptsetup", &args, new_secret)
}

/// Detached-header equivalent of `dump_volume_key` -- for extracting the
/// volume key when the currently-active header lives somewhere other
/// than `img`'s own front (a room slot's decrypted content staged to a
/// temp file, or a front-framed-encrypted header likewise staged) --
/// needed by `header::relocate`'s disable/rotate paths, which start
/// from a header that's already relocated.
pub fn dump_volume_key_detached(header: &Path, img: &Path, secret: &[u8]) -> Result<TempOutPath> {
    let out = TempOutPath::reserve("vk")?;
    let header_str = header.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();
    let out_str = out.path().to_string_lossy().into_owned();
    let _umask = proc::UmaskGuard::scoped_0077();
    proc::run_with_stdin(
        "cryptsetup",
        &["luksDump", "--header", &header_str, "--dump-master-key", "--batch-mode", "--master-key-file", &out_str, "--key-file", "-", &img_str],
        secret,
    )?;
    Ok(out)
}

/// Format a brand-new *default-sized* (not minimized) detached header at
/// `header_out`, forcing the same volume key -- used to restore a
/// normal, directly-cryptsetup-openable header at the container's front
/// when `headerOffset` is disabled (and `headerEncryption` is also off,
/// so the result needs no framing/decryption to be usable by plain
/// `cryptsetup open`). Mirrors `format_minimized_detached_header` minus
/// the `--luks2-metadata-size`/`--luks2-keyslots-size` flags, so
/// cryptsetup picks its own normal default sizing (matching what
/// `format_vault_ex` produces for a freshly created vault).
pub fn format_default_detached_header(
    header_out: &Path,
    img: &Path,
    new_secret: &[u8],
    volume_key_file: &Path,
    offset_bytes: u64,
    sector_size: u64,
    strength: Strength,
) -> Result<()> {
    if offset_bytes % 512 != 0 {
        return Err(CasError::new("data offset is not sector-aligned"));
    }
    let offset_sectors = (offset_bytes / 512).to_string();
    let sector_size_str = sector_size.to_string();
    let header_str = header_out.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();
    let vk_str = volume_key_file.to_string_lossy().into_owned();

    let mut args: Vec<&str> = vec![
        "luksFormat", "--batch-mode", "--type", "luks2",
        "--header", &header_str,
        "--offset", &offset_sectors,
        "--sector-size", &sector_size_str,
        "--volume-key-file", &vk_str,
        "--pbkdf", "argon2id",
    ];
    args.extend_from_slice(strength.pbkdf_args());
    args.push("--pbkdf-force-iterations");
    args.push(strength.iterations());
    args.push(&img_str);
    args.push("--key-file");
    args.push("-");

    let _umask = proc::UmaskGuard::scoped_0077();
    proc::run_with_stdin("cryptsetup", &args, new_secret)
}

/// Detached-header equivalent of `slot_cycle` -- same safe
/// write-new/verify/kill-old sequence, but every cryptsetup call is
/// pointed at `header` instead of `img`'s own front. Used when
/// `headerOffset` is enabled, since the container's real header no
/// longer lives where plain (non-`--header`) cryptsetup calls would
/// look for it.
pub fn slot_cycle_detached(ctx: &Ctx, header: &Path, img: &Path, old_secret: &[u8], new_secret: &[u8], strength: Option<Strength>) -> Result<()> {
    let header_str = header.to_string_lossy().into_owned();
    let img_str = img.to_string_lossy().into_owned();

    let old_slot = {
        let out = proc::capture("cryptsetup", &["luksDump", "--header", &header_str, &img_str]);
        let text = String::from_utf8_lossy(&out.stdout).to_string();
        let mut found = None;
        for line in text.lines() {
            let trimmed = line.trim_start();
            if let Some(colon) = trimmed.find(':') {
                let (num_part, _) = trimmed.split_at(colon);
                if !num_part.is_empty() && num_part.bytes().all(|b| b.is_ascii_digit()) {
                    if let Ok(n) = num_part.parse::<u32>() {
                        let slot_str = n.to_string();
                        if proc::run_with_stdin_status(
                            "cryptsetup",
                            &["open", "--header", &header_str, "--test-passphrase", "--key-slot", &slot_str, "--key-file", "-", &img_str],
                            old_secret,
                        ) {
                            found = Some(n);
                            break;
                        }
                    }
                }
            }
        }
        found.ok_or_else(|| CasError::new("current passphrase did not match any slot in the detached header"))?
    };

    let tf_old = TempKeyfile::write(old_secret)?;
    let tf_new = TempKeyfile::write(new_secret)?;
    let old_str = tf_old.path().to_string_lossy().into_owned();
    let new_str = tf_new.path().to_string_lossy().into_owned();

    // A minimized single-keyslot header (headerOffset's room slots) has
    // exactly one keyslot -- there's no free slot to add the new key
    // into alongside the old one the way the front-header slot_cycle
    // does. So this cycles by re-keying the existing (only) slot
    // directly via `luksChangeKey`, which cryptsetup performs
    // atomically at the slot level (the old key stops working and the
    // new one starts working as a single operation, not a two-step
    // add-then-remove) -- still safe, just a different primitive than
    // `slot_cycle`'s add/verify/kill for a header that has room for both.
    let mut args: Vec<&str> = vec!["luksChangeKey", "--batch-mode", "--header", &header_str, "--key-file", &old_str];
    if let Some(s) = strength {
        args.push("--pbkdf");
        args.push("argon2id");
        args.extend_from_slice(s.pbkdf_args());
        args.push("--pbkdf-force-iterations");
        args.push(s.iterations());
    }
    args.push(&img_str);
    args.push(&new_str);
    logf!(ctx, "  [1/2] re-keying detached header slot {old_slot} ...");
    proc::run("cryptsetup", &args)?;

    logf!(ctx, "  [2/2] verifying ...");
    if !test_detached(header, img, new_secret) {
        die!("verification failed after detached-header re-key — the header may be in an inconsistent state, do not scrub anything and investigate manually");
    }
    Ok(())
}

pub fn test(img: &Path, secret: &[u8]) -> bool {
    let img_str = img.to_string_lossy().into_owned();
    proc::run_with_stdin_status("cryptsetup", &["open", "--test-passphrase", "--key-file", "-", &img_str], secret)
}

/// Swap the LUKS key safely: find the slot `old_secret` unlocks, write
/// `new_secret` to a fresh free slot, verify the new slot actually opens
/// the vault, and only then kill the old slot (authorized with the new
/// key). A crash at any point before step 3 leaves the old key valid.
pub fn slot_cycle(ctx: &Ctx, img: &Path, old_secret: &[u8], new_secret: &[u8], strength: Option<Strength>) -> Result<()> {
    let old_slot = find_used_slot(img, old_secret)
        .ok_or_else(|| CasError::new("current passphrase did not match any LUKS slot"))?;
    let new_slot =
        find_free_slot(img, Some(old_slot)).ok_or_else(|| CasError::new("no free LUKS slots available"))?;

    let strength_note = strength.map(|s| format!(" (strength={s})")).unwrap_or_default();
    logf!(ctx, "  [1/3] writing new key to slot {new_slot}{strength_note} ...");
    add_key(img, old_secret, new_secret, strength, Some(new_slot))?;

    logf!(ctx, "  [2/3] verifying ...");
    if !test(img, new_secret) {
        let _ = remove_slot(img, new_slot, old_secret);
        die!("verification failed — rolled back, old key is still valid");
    }

    logf!(ctx, "  [3/3] removing old key from slot {old_slot} ...");
    remove_slot(img, old_slot, new_secret)
}

#[cfg(test)]
mod header_offset_tests {
    use super::*;

    fn old_secret_bytes_mapper() -> String {
        "cas_test_hdroffset_orig".to_string()
    }
    fn new_secret_mapper() -> String {
        "cas_test_hdroffset_new".to_string()
    }
    fn read_first_mb_sha256(dev: &str) -> [u8; 32] {
        use sha2::{Digest, Sha256};
        use std::io::Read;
        let mut f = std::fs::File::open(dev).unwrap();
        let mut buf = vec![0u8; 1024 * 1024];
        f.read_exact(&mut buf).unwrap();
        let mut h = Sha256::new();
        h.update(&buf);
        h.finalize().into()
    }
    use crate::config::Strength;

    /// Real end-to-end proof against a live scratch container (not a
    /// mock) that: (1) copying just the front 16 MiB into a separate
    /// file and detached-opening from the copy alone unlocks
    /// identically to a normal open -- header-position-independence in
    /// practice, not just in spec; (2) a brand-new *minimized*
    /// single-keyslot detached header, formatted with a fresh
    /// passphrase but a forced volume key extracted from the original
    /// container, also unlocks the exact same (untouched) payload --
    /// which is what actually lets a relocated header fit in a 384 KiB
    /// room slot instead of the full 16 MiB reservation. Marked
    /// `#[ignore]`: needs a real `cryptsetup` binary and scratch disk
    /// space, not something to run on every `cargo test`. Run with
    /// `cargo test --bin cas -- --ignored header_offset_tests`.
    #[test]
    #[ignore]
    fn detached_and_minimized_header_open_same_payload() {
        let dir = std::env::temp_dir().join("cas-luks-headertest");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let img = dir.join("scratch.img");
        std::fs::File::create(&img).unwrap();
        crate::proc::run("truncate", &["-s", "96M", img.to_str().unwrap()]).unwrap();

        let old_secret = b"scratchpass-orig".to_vec();
        format_vault_ex(&img, &old_secret, Strength::Light, false).unwrap();
        assert!(test(&img, &old_secret));

        // (1) full 16 MiB copy, detached test-open.
        let offset = data_offset_bytes(&img).expect("luksDump must report a data offset");
        assert_eq!(offset, 16 * 1024 * 1024, "cryptsetup's default data offset changed -- update this assumption");
        let header16 = dir.join("header16.img");
        crate::proc::run("dd", &[&format!("if={}", img.display()), &format!("of={}", header16.display()), "bs=1M", "count=16", "status=none"]).unwrap();
        assert!(test_detached(&header16, &img, &old_secret), "detached test-open from a raw 16 MiB header copy must succeed");

        // (2) minimized single-keyslot header, new passphrase, forced
        // same volume key -- must still unlock the same payload.
        // Crucially must also pin --sector-size to the original
        // container's own sector size: cryptsetup 2.8.6 defaults to
        // 4096-byte sectors for a normal luksFormat but 512 bytes for a
        // bare --header-mode format with no device to probe, and a
        // mismatch there produces a header that opens *structurally*
        // fine (test_detached alone would pass) while silently
        // decrypting every payload byte to garbage, since XTS's IV
        // depends on the sector number -- confirmed live 2026-08-16,
        // exactly the scenario the plan's "test-open succeeding isn't
        // sufficient proof" warning calls out.
        let sector_size = sector_size_bytes(&img).expect("luksDump must report a sector size");
        let vk = dump_volume_key(&img, &old_secret).unwrap();
        let new_secret = b"scratchpass-relocated".to_vec();
        let minihdr = dir.join("minihdr.img");
        format_minimized_detached_header(&minihdr, &img, &new_secret, vk.path(), offset, sector_size, Strength::Light).unwrap();
        let meta_bytes = std::fs::metadata(&minihdr).unwrap().len();
        assert!(meta_bytes <= crate::header::room::SLOT_SIZE, "minimized header ({meta_bytes} bytes) must fit in one room slot ({} bytes)", crate::header::room::SLOT_SIZE);
        assert!(test_detached(&minihdr, &img, &new_secret), "minimized detached header with forced volume key must unlock the same payload under its own new passphrase");

        // Real payload checksum comparison, not just a structural
        // test-open -- the actual proof this bug needed.
        let orig_dev = open_luks(&img, &old_secret_bytes_mapper(), &old_secret).unwrap();
        let orig_sum = read_first_mb_sha256(&orig_dev);
        crate::proc::run_silent("cryptsetup", &["close", &old_secret_bytes_mapper()]);
        let new_dev = open_luks_detached(&minihdr, &img, &new_secret_mapper(), &new_secret).unwrap();
        let new_sum = read_first_mb_sha256(&new_dev);
        crate::proc::run_silent("cryptsetup", &["close", &new_secret_mapper()]);
        assert_eq!(orig_sum, new_sum, "relocated minimized header must decrypt to the exact same payload bytes as the original, not just open structurally");

        // The old passphrase must no longer work against the *new*
        // minimized header (it's a different LUKS2 header/keyslot
        // entirely) -- confirms this isn't accidentally passing via
        // some fallback.
        assert!(!test_detached(&minihdr, &img, &old_secret));

        let _ = std::fs::remove_dir_all(&dir);
    }
}
