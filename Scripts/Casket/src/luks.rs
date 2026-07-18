// &desc: "cryptsetup wrappers: open/close a vault, enumerate/add/remove LUKS key slots, and the safe two-phase slot_cycle passphrase rotation."
use std::collections::HashSet;
use std::path::Path;

use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::logf;
use crate::proc::{self, TempKeyfile};

/// Format a freshly truncated image file as LUKS2 with the given KDF
/// cost preset. The secret goes over stdin, same as every other
/// cryptsetup call here — it never touches disk.
pub fn format_vault(img: &Path, secret: &[u8], strength: Strength) -> Result<()> {
    let img_str = img.to_string_lossy().into_owned();
    let mut args: Vec<&str> = vec!["luksFormat", "--batch-mode", "--pbkdf", "argon2id"];
    args.extend_from_slice(strength.pbkdf_args());
    args.push("--pbkdf-force-iterations");
    args.push(strength.iterations());
    args.push(&img_str);
    args.push("--key-file");
    args.push("-");
    proc::run_with_stdin("cryptsetup", &args, secret)
}

pub fn open_luks(img: &Path, mapper: &str, secret: &[u8]) -> Result<String> {
    let img_str = img.to_string_lossy().into_owned();
    proc::run_with_stdin("cryptsetup", &["open", "--key-file", "-", &img_str, mapper], secret)
        .map_err(|_| CasError::new("wrong passphrase or keyfile — could not unlock vault"))?;
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
