// &desc: "Enable/disable/verify orchestration for headerOffset and headerEncryption, plus relocate_if_enabled for the rotation hook. All four enable/disable paths, and rotation, share one discipline: derive the new content, write it somewhere the old (still-authoritative) location doesn't occupy, prove it's correct with a real detached open PLUS a payload checksum (a wrong volume key still opens 'successfully'), commit Meta to point at the new location, and only then scrub the old location with fresh CSPRNG bytes -- never in a different order. A crash between verify and commit leaves the old location still fully intact and still trusted; a crash between commit and scrub leaves the vault opening fine from the new (already-verified) location with the old one just inertly unscrubbed, finishable later by resume_scrub_if_pending. There is no ordering here under which a crash leaves a vault with no valid header anywhere.
//
// Design note / deviation from the plan text: the KDF's IKM here is the
// vault's own already-derived LUKS `secret` (passphrase bytes, or
// combined_secret(pw, keyfile) for a 2FA vault), not separately-framed
// raw passphrase+keyfile bytes. That's a deliberate simplification over
// the plan's literal 'IKM is passphrase bytes (+ keyfile bytes)' framing:
// using `secret` directly means every call site that already has the
// verified LUKS secret in hand (open.rs's check_tamper, gate.rs, the CLI
// dispatch layer) can also do header-room lookups/tamper ground-truth
// with zero extra plumbing, and there's no risk of a caller passing a
// differently-split IKM than the one used at enable time (which would
// silently point derive_slot_index at the wrong slot). The KDF module
// itself (header/mod.rs) is unchanged -- this only affects what's passed
// as `ikm_parts`."
use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use rand::RngCore;
use sha2::{Digest, Sha256};

use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::header::{self, room};
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::proc::TempOutPath;
use crate::tamper;
use crate::vault::Vault;

/// A minimized single-keyslot header (`header::room::SLOT_SIZE`'s doc
/// comment) is 290,816 bytes; framed+ChaCha20-Poly1305-encrypted that's
/// `12 (nonce) + 290816 + 16 (tag) = 290844`. Used by `ground_truth` to
/// tell "front holds a framed-encrypted header" apart from "front was
/// scrubbed to random filler after relocation" without needing the
/// secret to disambiguate structurally first.
const FRAMED_ENCRYPTED_MINIMIZED_LEN: u32 = 12 + 290_816 + 16;

/// How many bytes of the *unlocked* payload get hashed for the
/// verify-before-commit checksum comparison -- enough to catch a wrong
/// volume key (which decrypts to unrelated garbage from byte 0), cheap
/// enough to run on every enable/disable/rotate without noticeably
/// slowing them down.
const VERIFY_CHECKSUM_BYTES: usize = 4 * 1024 * 1024;

// --- framing -----------------------------------------------------------

/// 4-byte BE length prefix + data. Used for both room-slot storage
/// (slots are fixed-size and padded with random filler) and
/// front-framed-encrypted storage (the front region is padded to the
/// original data-offset boundary) -- neither location's raw capacity
/// equals the payload's real length, either because of random padding
/// (slots) or because ciphertext length varies from the plaintext
/// minimized header's fixed length (front, once AEAD tag+nonce are
/// added).
fn frame(data: &[u8]) -> Vec<u8> {
    let mut out = (data.len() as u32).to_be_bytes().to_vec();
    out.extend_from_slice(data);
    out
}

fn unframe(buf: &[u8]) -> Result<Vec<u8>> {
    if buf.len() < 4 {
        return Err(CasError::new("corrupt header frame: too short"));
    }
    let len = u32::from_be_bytes(buf[0..4].try_into().unwrap()) as usize;
    if buf.len() < 4 + len {
        return Err(CasError::new("corrupt header frame: declared length exceeds buffer"));
    }
    Ok(buf[4..4 + len].to_vec())
}

// --- AEAD ----------------------------------------------------------------

fn encrypt_header(key: &[u8; 32], plain: &[u8]) -> Vec<u8> {
    let cipher = ChaCha20Poly1305::new(key.into());
    let mut nonce_bytes = [0u8; 12];
    rand::thread_rng().fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ct = cipher.encrypt(nonce, plain).expect("chacha20poly1305 encrypt with valid static params never fails");
    let mut out = nonce_bytes.to_vec();
    out.extend_from_slice(&ct);
    out
}

fn decrypt_header(key: &[u8; 32], data: &[u8]) -> Result<Vec<u8>> {
    if data.len() < 12 {
        return Err(CasError::new("corrupt encrypted header: too short for a nonce"));
    }
    let (nonce_bytes, ct) = data.split_at(12);
    let cipher = ChaCha20Poly1305::new(key.into());
    cipher
        .decrypt(Nonce::from_slice(nonce_bytes), ct)
        .map_err(|_| CasError::new("header decryption failed — wrong key or corrupt data"))
}

// --- location I/O --------------------------------------------------------

/// The front region's length -- the original data offset (queried live
/// while the front still holds a valid, parseable header) if available,
/// else the standard 16 MiB this codebase's own default `luksFormat`
/// call always produces (confirmed live 2026-08-16, see luks.rs's
/// `header_offset_tests`). Only the "else" branch is ever hit once the
/// front has already been relocated away from (data_offset_bytes can no
/// longer parse it at that point).
fn front_region_len(img: &Path) -> u64 {
    luks::data_offset_bytes(img).unwrap_or(16 * 1024 * 1024)
}

fn place_at_front_native(img: &Path, header_bytes: &[u8]) -> Result<()> {
    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(0))?;
    f.write_all(header_bytes)?;
    f.flush()?;
    Ok(())
}

fn place_at_front_framed(img: &Path, data: &[u8], region_len: u64) -> Result<()> {
    let framed = frame(data);
    if framed.len() as u64 > region_len {
        return Err(CasError::new("encrypted header does not fit in the front region"));
    }
    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(0))?;
    f.write_all(&framed)?;
    let mut remaining = region_len - framed.len() as u64;
    let mut rng = rand::thread_rng();
    let mut buf = vec![0u8; 1024 * 1024];
    while remaining > 0 {
        let chunk = remaining.min(buf.len() as u64) as usize;
        rng.fill_bytes(&mut buf[..chunk]);
        f.write_all(&buf[..chunk])?;
        remaining -= chunk as u64;
    }
    f.flush()?;
    Ok(())
}

fn read_front_framed(img: &Path) -> Result<Vec<u8>> {
    let mut f = File::open(img)?;
    let mut len_buf = [0u8; 4];
    f.read_exact(&mut len_buf)?;
    let len = u32::from_be_bytes(len_buf) as usize;
    let mut data = vec![0u8; len];
    f.read_exact(&mut data)?;
    Ok(data)
}

fn place_at_slot(img: &Path, index: usize, data: &[u8]) -> Result<()> {
    room::write_slot(img, index as u64, &frame(data)).map_err(Into::into)
}

fn read_from_slot(img: &Path, index: usize) -> Result<Vec<u8>> {
    let buf = room::read_slot(img, index as u64).ok_or_else(|| CasError::new("header room slot not found — is the room provisioned?"))?;
    unframe(&buf)
}

/// Overwrite the front region with fresh CSPRNG bytes -- used both by
/// the enable-headerOffset scrub (after commit) and by the crash-window
/// resume check. A `CAS_TEST_SCRUB_DELAY_MS` env var, read once per
/// megabyte chunk, exists solely so the crash-window test can reliably
/// SIGKILL mid-overwrite; it's a no-op in normal use (unset).
fn scrub_front_region(img: &Path, region_len: u64) -> Result<()> {
    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(0))?;
    let mut rng = rand::thread_rng();
    let mut buf = vec![0u8; 1024 * 1024];
    let mut remaining = region_len;
    let delay_ms: Option<u64> = std::env::var("CAS_TEST_SCRUB_DELAY_MS").ok().and_then(|v| v.parse().ok());
    while remaining > 0 {
        let chunk = remaining.min(buf.len() as u64) as usize;
        rng.fill_bytes(&mut buf[..chunk]);
        f.write_all(&buf[..chunk])?;
        f.flush()?;
        remaining -= chunk as u64;
        if let Some(ms) = delay_ms {
            std::thread::sleep(std::time::Duration::from_millis(ms));
        }
    }
    Ok(())
}

fn scrub_slot(img: &Path, index: usize) -> Result<()> {
    room::scrub_slot(img, index as u64).map_err(Into::into)
}

/// Temporarily truncate `img` down to its true payload boundary (see
/// `room::container_boundary`'s doc comment for exactly why) for the
/// duration of `f`, then restore the exact same trailing bytes
/// afterward -- unconditionally, whether `f` succeeded or not. Every
/// `luks::format_minimized_detached_header`/`format_default_detached_header`
/// call in this file must go through this: confirmed live 2026-08-17
/// that calling either directly against an `img` that already has a
/// room appended silently destroys the room the instant the `luksFormat
/// --integrity` call runs (before any `cryptsetup open` even happens) --
/// dm-integrity's tag/journal init writes out to whatever the file's
/// *current* length is, not just the true payload.
///
/// Safe to nest/call repeatedly across enable/disable/rotate cycles:
/// each call only ever hides+restores whatever's really there right
/// now, so a room from three rebuilds ago is exactly as protected as
/// one from the most recent. Doesn't need its own crash-safety story on
/// top of what already exists elsewhere in this file -- the format call
/// itself only ever writes to a separate temp file
/// (`header_out`)/the container's own payload region, never to the
/// hidden tail bytes this holds in memory, so a crash mid-call just
/// means the tail is momentarily not on disk (recoverable by re-running
/// the same `cas` command, which starts from `stage_current_header`
/// reading wherever the header *actually* still is) rather than any
/// data being lost.
fn with_room_hidden<T>(img: &Path, f: impl FnOnce() -> Result<T>) -> Result<T> {
    let full_len = std::fs::metadata(img)?.len();
    let boundary = room::container_boundary(img);
    if boundary >= full_len {
        return f(); // nothing appended past the true payload -- no hiding needed
    }

    let mut tail = vec![0u8; (full_len - boundary) as usize];
    {
        let mut rf = File::open(img)?;
        rf.seek(SeekFrom::Start(boundary))?;
        rf.read_exact(&mut tail)?;
    }
    {
        let wf = OpenOptions::new().write(true).open(img)?;
        wf.set_len(boundary)?;
    }

    let result = f();

    let restore: Result<()> = (|| {
        let mut wf = OpenOptions::new().write(true).open(img)?;
        wf.seek(SeekFrom::Start(boundary))?;
        wf.write_all(&tail)?;
        wf.flush()?;
        Ok(())
    })();

    match (result, restore) {
        (Ok(v), Ok(())) => Ok(v),
        (Err(e), _) => Err(e),
        (Ok(_), Err(e)) => Err(e),
    }
}

// --- verification ---------------------------------------------------------

/// sha256 of the first `VERIFY_CHECKSUM_BYTES` of the unlocked mapper
/// device -- opened detached if `header` is `Some`, plain otherwise.
/// Always closes the mapper before returning, success or failure.
fn payload_checksum(img: &Path, header: Option<&Path>, mapper: &str, secret: &[u8]) -> Result<[u8; 32]> {
    if Path::new(&format!("/dev/mapper/{mapper}")).exists() {
        crate::proc::run_silent("cryptsetup", &["close", mapper]);
    }
    let dev = match header {
        Some(h) => luks::open_luks_detached(h, img, mapper, secret)?,
        None => luks::open_luks(img, mapper, secret)?,
    };
    let result = (|| -> Result<[u8; 32]> {
        let mut f = File::open(&dev)?;
        let mut buf = vec![0u8; VERIFY_CHECKSUM_BYTES];
        f.read_exact(&mut buf)?;
        let mut hasher = Sha256::new();
        hasher.update(&buf);
        Ok(hasher.finalize().into())
    })();
    crate::proc::run_silent("cryptsetup", &["close", mapper]);
    result
}

/// Real detached test-open PLUS a payload checksum comparison against
/// `reference` -- `cryptsetup open` succeeding on a wrong/mismatched
/// volume key still looks like success structurally, it just decrypts
/// the payload to garbage, so the checksum is the actual proof.
fn verify_new_header(vault: &Vault, header_path: &Path, secret: &[u8], reference_checksum: [u8; 32]) -> Result<()> {
    if !luks::test_detached(header_path, &vault.img, secret) {
        return Err(CasError::new("verification failed: new header does not structurally decrypt with the given secret"));
    }
    let mapper = format!("{}_hv", vault.mapper);
    let got = payload_checksum(&vault.img, Some(header_path), &mapper, secret)?;
    if got != reference_checksum {
        return Err(CasError::new("verification failed: new header opens, but decrypts to different payload bytes than the original — refusing to commit"));
    }
    Ok(())
}

fn reference_checksum(vault: &Vault, current_header: Option<&Path>, secret: &[u8]) -> Result<[u8; 32]> {
    let mapper = format!("{}_hvref", vault.mapper);
    payload_checksum(&vault.img, current_header, &mapper, secret)
}

// --- current-location resolution ------------------------------------------

/// Stage the currently-active header's plaintext bytes into a fresh temp
/// file, regardless of which of the four states it's actually in. Used
/// as the read side of every enable/disable/rotate path (they all start
/// from "wherever the header is right now").
pub fn stage_current_header(vault: &Vault, meta: &Meta, master: Option<&[u8; 32]>) -> Result<TempOutPath> {
    let out = TempOutPath::reserve("hdr")?;
    let bytes = match (meta.header_offset == Some(true), meta.header_encryption == Some(true)) {
        (false, false) => {
            // native front -- just the container's own current header
            // bytes, whatever size cryptsetup itself is using.
            let len = front_region_len(&vault.img);
            let mut f = File::open(&vault.img)?;
            let mut buf = vec![0u8; len as usize];
            f.read_exact(&mut buf)?;
            buf
        }
        (false, true) => {
            let master = master.ok_or_else(|| CasError::new("header master secret required to read an encrypted front header"))?;
            let key = header::derive_header_key(master);
            let framed = read_front_framed(&vault.img)?;
            decrypt_header(&key, &framed)?
        }
        (true, false) => {
            let master = master.ok_or_else(|| CasError::new("header master secret required to locate a relocated header"))?;
            let slot = header::derive_slot_index(master, room::N_SLOTS as usize);
            read_from_slot(&vault.img, slot)?
        }
        (true, true) => {
            let master = master.ok_or_else(|| CasError::new("header master secret required to locate a relocated header"))?;
            let slot = header::derive_slot_index(master, room::N_SLOTS as usize);
            let key = header::derive_header_key(master);
            let framed = read_from_slot(&vault.img, slot)?;
            decrypt_header(&key, &framed)?
        }
    };
    out.write_secure(&bytes)?;
    Ok(out)
}

pub fn is_native_front(meta: &Meta) -> bool {
    meta.header_offset != Some(true) && meta.header_encryption != Some(true)
}

/// Verify `secret` against the vault's header wherever it currently
/// lives, per `meta` -- unlike a bare `luks::test`, this works
/// correctly even when the header isn't front-resident/plain anymore.
/// CLI dispatch (`header_offset.rs`/`header_encryption.rs`) uses this
/// instead of `luks::test` for exactly that reason: `luks::test` only
/// proves anything when `is_native_front(meta)` is true.
///
/// Falls back to a location-independent probe (`probe_location`) if
/// `meta`'s claimed location doesn't pan out, rather than concluding
/// the secret is wrong outright -- `meta.header_offset`/
/// `meta.header_encryption` are themselves HMAC-covered, tamperable
/// fields (see `tamper.rs`), so a hand-edit to *those* specific fields
/// means the meta-directed lookup here fails structurally even with the
/// correct secret. Without this fallback, `open.rs`'s `check_tamper`
/// call (which needs this to return `true` before it will even look at
/// the HMAC) can never reach the tamper branch for exactly the two
/// fields the tamper check exists to protect -- confirmed live
/// 2026-08-17 by hand-flipping `header_offset` in the trailer and
/// re-opening with the correct passphrase.
pub fn verify_current_secret(vault: &Vault, meta: &Meta, secret: &[u8]) -> bool {
    let meta_directed = if is_native_front(meta) {
        luks::test(&vault.img, secret)
    } else {
        room::read_salt(&vault.img).is_some_and(|salt| {
            let master = header::derive_master_secret(&[secret], &salt);
            match stage_current_header(vault, meta, Some(&master)) {
                Ok(staged) => luks::test_detached(staged.path(), &vault.img, secret),
                Err(_) => false,
            }
        })
    };
    meta_directed || probe_location(&vault.img, secret).is_some()
}

// --- public API: state -----------------------------------------------------

pub fn offset_enabled(meta: &Meta) -> bool {
    meta.header_offset == Some(true)
}

pub fn encryption_enabled(meta: &Meta) -> bool {
    meta.header_encryption == Some(true)
}

// --- public API: room-layout migration --------------------------------------

/// Bring an existing header room up to the current slot layout if it's
/// still on an older one. Must run (after `Meta::strip`, before any
/// `room::read_salt`/slot lookup) at the top of every enable/disable/
/// rotate path below -- `header::derive_slot_index` always divides by
/// whatever `room::N_SLOTS` this build defines, so a v1 room's still-live
/// slot content would otherwise get looked up at the wrong v2 address the
/// moment `SLOT_SIZE`/`N_SLOTS` changed underneath it (exactly what
/// happened when `SLOT_SIZE` grew 384 KiB -> 768 KiB to fit an
/// integrity-formatted header -- see `header::room::SLOT_SIZE`'s doc
/// comment). No-op if there's no room yet, or it's already current.
///
/// The old v1 slot's bytes are moved, not re-derived or re-encrypted --
/// whatever's stored (a plain minimized header, or a
/// ChaCha20-Poly1305-encrypted one) is copied byte-for-byte to its new
/// v2 address, verified there, and only then is the room version byte
/// flipped. A crash before that flip leaves the v1 layout still fully
/// authoritative (the v2 write is inert filler until the flip commits);
/// a crash after it leaves the v2 location already verified and
/// authoritative. The old slot is scrubbed only after the flip commits,
/// same discipline as every other relocation in this file.
pub fn migrate_room_if_needed(ctx: &Ctx, vault: &Vault, meta: &Meta, secret: &[u8]) -> Result<()> {
    let Some(version) = room::room_version(&vault.img) else {
        return Ok(()); // no room provisioned yet -- nothing to migrate
    };
    if version >= room::ROOM_VERSION {
        return Ok(());
    }
    if version != 1 {
        return Err(CasError::new(format!("header room has unrecognized version {version} — refusing to guess a migration path")));
    }

    let salt = room::read_salt(&vault.img).ok_or_else(|| CasError::new("header room magic present but salt unreadable"))?;
    let master = header::derive_master_secret(&[secret], &salt);

    if !offset_enabled(meta) {
        // The room exists (someone enabled headerOffset at some point)
        // but nothing currently lives in a v1 slot -- either headerOffset
        // was since disabled (content already moved back to the front),
        // or this is a fresh room `ensure_provisioned` is about to use
        // for the first time. Either way there are no live bytes to
        // relocate: just stamp the current version so future opens don't
        // pay this check's cost again.
        room::set_room_version(&vault.img, room::ROOM_VERSION)?;
        return Ok(());
    }

    logf!(ctx, "  [i] migrating header room to the current (integrity-capable) slot layout ...");
    let old_slot = header::derive_slot_index(&master, room::V1_N_SLOTS as usize) as u64;
    let framed_old = room::read_slot_v1(&vault.img, old_slot).ok_or_else(|| CasError::new("could not read the existing v1 header room slot"))?;

    // Reference: the vault must still open via the *old* location before
    // we touch anything -- if it doesn't, something's already wrong
    // upstream of this migration and we must not make it worse.
    let raw_old = if encryption_enabled(meta) {
        let key = header::derive_header_key(&master);
        decrypt_header(&key, &unframe(&framed_old)?)?
    } else {
        unframe(&framed_old)?
    };
    let staged_old = TempOutPath::reserve("hdr")?;
    staged_old.write_secure(&raw_old)?;
    if !luks::test_detached(staged_old.path(), &vault.img, secret) {
        return Err(CasError::new("v1 header room migration aborted: existing slot content does not decrypt with the given secret"));
    }
    let reference = payload_checksum(&vault.img, Some(staged_old.path()), &format!("{}_hvref", vault.mapper), secret)?;

    let new_slot = header::derive_slot_index(&master, room::N_SLOTS as usize) as u64;
    room::write_slot(&vault.img, new_slot, &framed_old)?;

    let verify_result = verify_new_header(vault, staged_old.path(), secret, reference);
    if let Err(e) = verify_result {
        // New slot write is just inert filler until the version byte
        // flips below -- nothing to roll back, the v1 layout (version
        // byte still 1) is still fully authoritative.
        return Err(e);
    }

    room::set_room_version(&vault.img, room::ROOM_VERSION)?;
    logf!(ctx, "  [i] header room migrated — scrubbing the old v1 slot ...");
    room::scrub_slot_v1(&vault.img, old_slot)?;
    Ok(())
}

// --- public API: enable/disable --------------------------------------------

/// Enable `headerOffset`: relocate the header (native front bytes, or
/// whatever it currently is if headerEncryption is already on) into a
/// passphrase-derived room slot.
pub fn enable_offset(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    if offset_enabled(meta) {
        die!("headerOffset is already enabled");
    }
    // Every function below strips the trailer up front and keeps it
    // stripped for the whole operation (sector-size alignment — see
    // below). If anything fails partway through, `?` would otherwise
    // propagate straight out with the trailer still stripped and never
    // written back, silently losing the vault's *entire* metadata
    // trailer (not just the header-hiding fields) on the very first
    // error — confirmed live 2026-08-17 as a real bug, not a
    // theoretical one. `original` is the pre-call snapshot, restored
    // verbatim on any error path.
    let original = meta.clone();
    let result = enable_offset_inner(ctx, vault, meta, secret, strength);
    if result.is_err() {
        let _ = original.write(&vault.img);
    }
    result
}

fn enable_offset_inner(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    // Keep the trailer stripped for the *entire* operation, not just
    // through provisioning -- `format_minimized_detached_header`'s
    // `--sector-size` (see luks.rs) requires the device's remaining
    // size past the data offset to be sector-size-aligned, and
    // re-attaching the trailer (a small, arbitrary-length JSON blob)
    // partway through would break that alignment. Room provisioning is
    // independently idempotent via its own on-disk magic check (not
    // `meta.header_room`), so it's safe to leave that field's
    // persistence to the single real commit below rather than writing
    // it early.
    Meta::strip(&vault.img)?;
    migrate_room_if_needed(ctx, vault, meta, secret)?;
    let salt = room::ensure_provisioned(&vault.img)?;
    meta.header_room = Some(true);

    let master = header::derive_master_secret(&[secret], &salt);
    let slot = header::derive_slot_index(&master, room::N_SLOTS as usize);

    let offset_bytes = luks::data_offset_bytes(&vault.img)
        .ok_or_else(|| CasError::new("could not determine the current LUKS data offset"))?;
    let sector_size = luks::sector_size_bytes(&vault.img)
        .ok_or_else(|| CasError::new("could not determine the current LUKS sector size"))?;
    let integrity = luks::has_integrity(&vault.img);
    let vk = luks::dump_volume_key(&vault.img, secret)?;

    let want_encryption = encryption_enabled(meta);
    logf!(ctx, "  [1/4] building a minimized header with the existing volume key ...");
    let minihdr = TempOutPath::reserve("hdr")?;
    with_room_hidden(&vault.img, || {
        luks::format_minimized_detached_header(minihdr.path(), &vault.img, secret, vk.path(), offset_bytes, sector_size, strength, integrity)
    })?;
    let plain_bytes = std::fs::read(minihdr.path())?;

    let stored_bytes = if want_encryption {
        let key = header::derive_header_key(&master);
        encrypt_header(&key, &plain_bytes)
    } else {
        plain_bytes
    };

    logf!(ctx, "  [2/4] verifying against the original, unchanged front ...");
    let reference = reference_checksum(vault, None, secret)?;
    place_at_slot(&vault.img, slot, &stored_bytes)?;
    let verify_result = (|| -> Result<()> {
        let staged = TempOutPath::reserve("hdr")?;
        let raw = if want_encryption {
            let key = header::derive_header_key(&master);
            decrypt_header(&key, &stored_bytes)?
        } else {
            stored_bytes.clone()
        };
        staged.write_secure(&raw)?;
        verify_new_header(vault, staged.path(), secret, reference)
    })();
    if let Err(e) = verify_result {
        // Old (front) location is still fully untouched — nothing to
        // roll back there. Just leave the slot write in place (it's
        // just garbage in an unused slot until a real enable succeeds)
        // and refuse to commit.
        return Err(e);
    }

    logf!(ctx, "  [3/4] committing ...");
    meta.header_offset = Some(true);
    tamper::refresh(secret, meta);
    meta.write(&vault.img)?;

    logf!(ctx, "  [4/4] scrubbing the old front location ...");
    scrub_front_region(&vault.img, offset_bytes)?;
    Ok(())
}

/// Disable `headerOffset`: relocate the header from its room slot back
/// to the front, restoring a normal default-sized detached header if
/// headerEncryption is off (so plain `cryptsetup open` works again with
/// no `--header`), or a minimized+framed+encrypted one at the front if
/// headerEncryption is still on.
pub fn disable_offset(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    if !offset_enabled(meta) {
        die!("headerOffset is not enabled");
    }
    let original = meta.clone();
    let result = disable_offset_inner(ctx, vault, meta, secret, strength);
    if result.is_err() {
        let _ = original.write(&vault.img);
    }
    result
}

fn disable_offset_inner(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    // Same alignment reasoning as enable_offset: keep the trailer off
    // for the whole operation so the format calls' `--sector-size`
    // device-size check isn't thrown off by a re-attached trailer.
    Meta::strip(&vault.img)?;
    migrate_room_if_needed(ctx, vault, meta, secret)?;

    let salt = room::read_salt(&vault.img).ok_or_else(|| CasError::new("header room not found — vault metadata is inconsistent"))?;
    let master = header::derive_master_secret(&[secret], &salt);
    let slot = header::derive_slot_index(&master, room::N_SLOTS as usize);

    let want_encryption = encryption_enabled(meta);
    let staged_current = stage_current_header(vault, meta, Some(&master))?;

    logf!(ctx, "  [1/4] extracting the volume key from the current (relocated) header ...");
    let vk = luks::dump_volume_key_detached(staged_current.path(), &vault.img, secret)?;
    let offset_bytes = luks::data_offset_bytes_from_header(staged_current.path(), &vault.img)
        .or_else(|| luks::data_offset_bytes(&vault.img))
        .ok_or_else(|| CasError::new("could not determine the LUKS data offset from the relocated header"))?;
    let sector_size = luks::sector_size_bytes_from_header(staged_current.path(), &vault.img)
        .or_else(|| luks::sector_size_bytes(&vault.img))
        .ok_or_else(|| CasError::new("could not determine the LUKS sector size from the relocated header"))?;
    let integrity = luks::has_integrity_from_header(staged_current.path(), &vault.img);

    logf!(ctx, "  [2/4] building the front-resident replacement header ...");
    let front_region = front_region_len_for_restore(offset_bytes);
    let (stored_bytes, place_native): (Vec<u8>, bool) = if want_encryption {
        let minihdr = TempOutPath::reserve("hdr")?;
        with_room_hidden(&vault.img, || {
            luks::format_minimized_detached_header(minihdr.path(), &vault.img, secret, vk.path(), offset_bytes, sector_size, strength, integrity)
        })?;
        let plain = std::fs::read(minihdr.path())?;
        let key = header::derive_header_key(&master);
        (encrypt_header(&key, &plain), false)
    } else {
        let full = TempOutPath::reserve("hdr")?;
        with_room_hidden(&vault.img, || {
            luks::format_default_detached_header(full.path(), &vault.img, secret, vk.path(), offset_bytes, sector_size, strength, integrity)
        })?;
        (std::fs::read(full.path())?, true)
    };

    logf!(ctx, "  [3/4] verifying against the current relocated header, unchanged ...");
    let reference = reference_checksum(vault, Some(staged_current.path()), secret)?;
    let verify_result = (|| -> Result<()> {
        let staged = TempOutPath::reserve("hdr")?;
        if place_native {
            staged.write_secure(&stored_bytes)?;
        } else {
            let key = header::derive_header_key(&master);
            let raw = decrypt_header(&key, &stored_bytes)?;
            staged.write_secure(&raw)?;
        }
        verify_new_header(vault, staged.path(), secret, reference)
    })();
    verify_result?;

    // Commit: write the verified bytes to the front, flip Meta, THEN
    // scrub the slot — never the other order.
    if place_native {
        place_at_front_native(&vault.img, &stored_bytes)?;
    } else {
        place_at_front_framed(&vault.img, &stored_bytes, front_region)?;
    }
    meta.header_offset = Some(false);
    tamper::refresh(secret, meta);
    meta.write(&vault.img)?;

    logf!(ctx, "  [4/4] scrubbing the old room slot ...");
    scrub_slot(&vault.img, slot)?;
    Ok(())
}

/// Enable `headerEncryption`: AEAD-encrypt the header wherever it
/// currently lives (front or room slot), in place — no location change,
/// so no old/new location split. Still verify-before-mutate: the
/// encrypted candidate is proven via a scratch temp file (decrypted
/// back out) before the real location's bytes are overwritten.
pub fn enable_encryption(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    if encryption_enabled(meta) {
        die!("headerEncryption is already enabled");
    }
    let original = meta.clone();
    let result = enable_encryption_inner(ctx, vault, meta, secret, strength);
    if result.is_err() {
        let _ = original.write(&vault.img);
    }
    result
}

fn enable_encryption_inner(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    if offset_enabled(meta) {
        migrate_room_if_needed(ctx, vault, meta, secret)?;
        let salt = room::read_salt(&vault.img).ok_or_else(|| CasError::new("header room not found"))?;
        let master = header::derive_master_secret(&[secret], &salt);
        let slot = header::derive_slot_index(&master, room::N_SLOTS as usize);
        let plain = read_from_slot(&vault.img, slot)?;
        let key = header::derive_header_key(&master);
        let cipher = encrypt_header(&key, &plain);

        logf!(ctx, "  [1/2] verifying the encrypted candidate ...");
        let reference = reference_checksum(vault, None, secret).or_else(|_| {
            let staged = TempOutPath::reserve("hdr")?;
            staged.write_secure(&plain)?;
            let mapper = format!("{}_hvref", vault.mapper);
            payload_checksum(&vault.img, Some(staged.path()), &mapper, secret)
        })?;
        let staged = TempOutPath::reserve("hdr")?;
        staged.write_secure(&decrypt_header(&key, &cipher)?)?;
        verify_new_header(vault, staged.path(), secret, reference)?;

        logf!(ctx, "  [2/2] committing ...");
        place_at_slot(&vault.img, slot, &cipher)?;
        meta.header_encryption = Some(true);
        tamper::refresh(secret, meta);
        meta.write(&vault.img)?;
    } else {
        // Trailer stays stripped for the whole operation -- same
        // sector-size-alignment reasoning as enable_offset. header_room
        // is persisted at the single real commit below, not here;
        // ensure_provisioned's own on-disk check makes re-running this
        // safe regardless.
        Meta::strip(&vault.img)?;
        migrate_room_if_needed(ctx, vault, meta, secret)?;
        let salt = room::ensure_provisioned(&vault.img)?;
        meta.header_room = Some(true);
        let master = header::derive_master_secret(&[secret], &salt);

        let offset_bytes = luks::data_offset_bytes(&vault.img).ok_or_else(|| CasError::new("could not determine the LUKS data offset"))?;
        let sector_size = luks::sector_size_bytes(&vault.img).ok_or_else(|| CasError::new("could not determine the LUKS sector size"))?;
        let integrity = luks::has_integrity(&vault.img);
        let vk = luks::dump_volume_key(&vault.img, secret)?;
        logf!(ctx, "  [1/2] building a minimized encrypted header for the front ...");
        let minihdr = TempOutPath::reserve("hdr")?;
        with_room_hidden(&vault.img, || {
            luks::format_minimized_detached_header(minihdr.path(), &vault.img, secret, vk.path(), offset_bytes, sector_size, strength, integrity)
        })?;
        let plain = std::fs::read(minihdr.path())?;
        let key = header::derive_header_key(&master);
        let cipher = encrypt_header(&key, &plain);

        let reference = reference_checksum(vault, None, secret)?;
        let staged = TempOutPath::reserve("hdr")?;
        staged.write_secure(&plain)?;
        verify_new_header(vault, staged.path(), secret, reference)?;

        logf!(ctx, "  [2/2] committing ...");
        let front_region = front_region_len(&vault.img);
        place_at_front_framed(&vault.img, &cipher, front_region)?;
        meta.header_encryption = Some(true);
        tamper::refresh(secret, meta);
        meta.write(&vault.img)?;
        // The plaintext minimized header briefly sat where the full
        // native header used to be (front_region bytes were only
        // partially overwritten by the framed write above if the
        // framed blob is shorter than the original real header) — the
        // framed write already padded the remainder with fresh random
        // filler, so there's no separate scrub step needed here (unlike
        // enable_offset, there's no *second* location left holding
        // stale plaintext).
    }
    Ok(())
}

/// Disable `headerEncryption`: replace the encrypted header (wherever
/// it lives) with a plain one in the same location — again in-place,
/// verified via a scratch temp file first.
pub fn disable_encryption(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    if !encryption_enabled(meta) {
        die!("headerEncryption is not enabled");
    }
    let original = meta.clone();
    let result = disable_encryption_inner(ctx, vault, meta, secret, strength);
    if result.is_err() {
        let _ = original.write(&vault.img);
    }
    result
}

fn disable_encryption_inner(ctx: &Ctx, vault: &Vault, meta: &mut Meta, secret: &[u8], strength: Strength) -> Result<()> {
    if offset_enabled(meta) {
        migrate_room_if_needed(ctx, vault, meta, secret)?;
        let salt = room::read_salt(&vault.img).ok_or_else(|| CasError::new("header room not found"))?;
        let master = header::derive_master_secret(&[secret], &salt);
        let slot = header::derive_slot_index(&master, room::N_SLOTS as usize);
        let key = header::derive_header_key(&master);
        let cipher = read_from_slot(&vault.img, slot)?;
        let plain = decrypt_header(&key, &cipher)?;

        logf!(ctx, "  [1/2] verifying the plaintext candidate ...");
        let staged = TempOutPath::reserve("hdr")?;
        staged.write_secure(&plain)?;
        let reference = reference_checksum(vault, None, secret).unwrap_or_else(|_| [0u8; 32]);
        let reference = if reference == [0u8; 32] {
            let mapper = format!("{}_hvref", vault.mapper);
            payload_checksum(&vault.img, Some(staged.path()), &mapper, secret)?
        } else {
            reference
        };
        verify_new_header(vault, staged.path(), secret, reference)?;

        logf!(ctx, "  [2/2] committing ...");
        place_at_slot(&vault.img, slot, &plain)?;
        meta.header_encryption = Some(false);
        tamper::refresh(secret, meta);
        meta.write(&vault.img)?;
    } else {
        // format_default_detached_header below needs the trailer off
        // for the same sector-size-alignment reason as enable_offset.
        Meta::strip(&vault.img)?;
        migrate_room_if_needed(ctx, vault, meta, secret)?;
        let key_master;
        let (master, key) = {
            let salt = room::read_salt(&vault.img).ok_or_else(|| CasError::new("header room not found"))?;
            key_master = header::derive_master_secret(&[secret], &salt);
            let key = header::derive_header_key(&key_master);
            (&key_master, key)
        };
        let cipher = read_front_framed(&vault.img)?;
        let plain = decrypt_header(&key, &cipher)?;

        // Restore a *default-sized* native header at the front so plain
        // `cryptsetup open` (no `--header`) works again — the minimized
        // one that was encrypted in place is too small to be a normal
        // container header (it was purpose-built minimal for a 384 KiB
        // room slot), so this rebuilds a normal one with the same
        // volume key rather than just writing `plain` back raw. Staged
        // once into `staged_plain` and reused for every lookup below —
        // an earlier version staged it into a block-scoped temp file
        // whose `Drop` deleted it before `data_offset_bytes_from_header`
        // ever read it back; keeping one live `TempOutPath` in scope for
        // the whole branch avoids that class of bug entirely.
        let staged_plain = TempOutPath::reserve("hdr")?;
        staged_plain.write_secure(&plain)?;
        let offset_bytes = luks::data_offset_bytes_from_header(staged_plain.path(), &vault.img)
            .ok_or_else(|| CasError::new("could not determine the LUKS data offset from the encrypted header"))?;
        let sector_size = luks::sector_size_bytes_from_header(staged_plain.path(), &vault.img)
            .ok_or_else(|| CasError::new("could not determine the LUKS sector size from the encrypted header"))?;
        let integrity = luks::has_integrity_from_header(staged_plain.path(), &vault.img);
        let vk = luks::dump_volume_key_detached(staged_plain.path(), &vault.img, secret)?;

        let full = TempOutPath::reserve("hdr")?;
        with_room_hidden(&vault.img, || {
            luks::format_default_detached_header(full.path(), &vault.img, secret, vk.path(), offset_bytes, sector_size, strength, integrity)
        })?;
        let full_bytes = std::fs::read(full.path())?;

        logf!(ctx, "  [1/2] verifying the plaintext front replacement ...");
        let reference = {
            let mapper = format!("{}_hvref", vault.mapper);
            payload_checksum(&vault.img, Some(staged_plain.path()), &mapper, secret)?
        };
        verify_new_header(vault, full.path(), secret, reference)?;
        let _ = master;

        logf!(ctx, "  [2/2] committing ...");
        place_at_front_native(&vault.img, &full_bytes)?;
        meta.header_encryption = Some(false);
        tamper::refresh(secret, meta);
        meta.write(&vault.img)?;
    }
    Ok(())
}

fn front_region_len_for_restore(offset_bytes: u64) -> u64 {
    offset_bytes.max(16 * 1024 * 1024)
}

// --- public API: rotation ---------------------------------------------------

/// Called after `slot_cycle`/`slot_cycle_detached` has already succeeded
/// (old passphrase invalid, new one valid), before the caller's own
/// `meta.write()`. No-op if neither toggle is on. Re-derives the new
/// master secret/slot from `new_secret` and relocates under the same
/// verify-before-scrub discipline as enable — parameterized by old vs.
/// new secret instead of "was disabled, now enabled".
pub fn relocate_if_enabled(ctx: &Ctx, vault: &Vault, meta: &mut Meta, old_secret: &[u8], new_secret: &[u8], strength: Option<Strength>) -> Result<()> {
    if !offset_enabled(meta) && !encryption_enabled(meta) {
        return Ok(());
    }
    let strength = strength.unwrap_or_default();
    // Defensive/idempotent: callers (passwd.rs/twofa.rs) already strip
    // before slot_cycle and don't write in between, but a stripped file
    // with no trailer strips to a no-op here, so this is safe either
    // way and makes this function self-contained against future callers
    // that don't happen to follow that same discipline.
    Meta::strip(&vault.img)?;
    migrate_room_if_needed(ctx, vault, meta, old_secret)?;

    if offset_enabled(meta) {
        let old_salt = room::read_salt(&vault.img).ok_or_else(|| CasError::new("header room not found"))?;
        let old_master = header::derive_master_secret(&[old_secret], &old_salt);
        let old_slot = header::derive_slot_index(&old_master, room::N_SLOTS as usize);

        let want_encryption = encryption_enabled(meta);
        let staged_current = stage_current_header(vault, meta, Some(&old_master))?;
        let vk = luks::dump_volume_key_detached(staged_current.path(), &vault.img, old_secret)?;
        let offset_bytes = luks::data_offset_bytes_from_header(staged_current.path(), &vault.img)
            .ok_or_else(|| CasError::new("could not determine the LUKS data offset from the current header"))?;
        let sector_size = luks::sector_size_bytes_from_header(staged_current.path(), &vault.img)
            .ok_or_else(|| CasError::new("could not determine the LUKS sector size from the current header"))?;
        let integrity = luks::has_integrity_from_header(staged_current.path(), &vault.img);

        // Room salt is fixed at provisioning time (it's what "room"
        // means) so the new slot index is derived from the *new*
        // secret against the *same* salt — a passphrase rotation moves
        // which slot is used, it doesn't reprovision the room.
        let new_master = header::derive_master_secret(&[new_secret], &old_salt);
        let new_slot = header::derive_slot_index(&new_master, room::N_SLOTS as usize);

        logf!(ctx, "  [header] rotating relocated header to a new slot under the new passphrase ...");
        let minihdr = TempOutPath::reserve("hdr")?;
        with_room_hidden(&vault.img, || {
            luks::format_minimized_detached_header(minihdr.path(), &vault.img, new_secret, vk.path(), offset_bytes, sector_size, strength, integrity)
        })?;
        let plain = std::fs::read(minihdr.path())?;
        let stored = if want_encryption {
            let key = header::derive_header_key(&new_master);
            encrypt_header(&key, &plain)
        } else {
            plain.clone()
        };

        let reference = reference_checksum(vault, Some(staged_current.path()), old_secret)?;
        let staged_new = TempOutPath::reserve("hdr")?;
        staged_new.write_secure(&plain)?;
        verify_new_header(vault, staged_new.path(), new_secret, reference)?;

        if new_slot == old_slot {
            // Extremely unlikely (1/85) but possible — same in-place
            // overwrite reasoning as enable_encryption, no separate old
            // location to scrub afterward.
            place_at_slot(&vault.img, new_slot, &stored)?;
        } else {
            place_at_slot(&vault.img, new_slot, &stored)?;
        }
        tamper::refresh(new_secret, meta);
        meta.write(&vault.img)?;

        if new_slot != old_slot {
            logf!(ctx, "  [header] scrubbing the old slot ...");
            scrub_slot(&vault.img, old_slot)?;
        }
    } else if encryption_enabled(meta) {
        // headerEncryption alone, front-resident — content changes (new
        // key from the new secret) but location doesn't, so this is an
        // in-place re-encrypt, same shape as enable_encryption's
        // no-offset branch.
        let salt = room::read_salt(&vault.img).ok_or_else(|| CasError::new("header room not found"))?;
        let old_master = header::derive_master_secret(&[old_secret], &salt);
        let old_key = header::derive_header_key(&old_master);
        let cipher = read_front_framed(&vault.img)?;
        let plain = decrypt_header(&old_key, &cipher)?;

        let staged_old = TempOutPath::reserve("hdr")?;
        staged_old.write_secure(&plain)?;
        let vk = luks::dump_volume_key_detached(staged_old.path(), &vault.img, old_secret)?;
        let offset_bytes = luks::data_offset_bytes_from_header(staged_old.path(), &vault.img)
            .ok_or_else(|| CasError::new("could not determine the LUKS data offset"))?;
        let sector_size = luks::sector_size_bytes_from_header(staged_old.path(), &vault.img)
            .ok_or_else(|| CasError::new("could not determine the LUKS sector size"))?;
        let integrity = luks::has_integrity_from_header(staged_old.path(), &vault.img);

        let new_master = header::derive_master_secret(&[new_secret], &salt);
        let minihdr = TempOutPath::reserve("hdr")?;
        with_room_hidden(&vault.img, || {
            luks::format_minimized_detached_header(minihdr.path(), &vault.img, new_secret, vk.path(), offset_bytes, sector_size, strength, integrity)
        })?;
        let new_plain = std::fs::read(minihdr.path())?;
        let new_key = header::derive_header_key(&new_master);
        let new_cipher = encrypt_header(&new_key, &new_plain);

        let reference = {
            let mapper = format!("{}_hvref", vault.mapper);
            payload_checksum(&vault.img, Some(staged_old.path()), &mapper, old_secret)?
        };
        let staged_new = TempOutPath::reserve("hdr")?;
        staged_new.write_secure(&new_plain)?;
        verify_new_header(vault, staged_new.path(), new_secret, reference)?;

        let front_region = front_region_len_for_restore(offset_bytes);
        place_at_front_framed(&vault.img, &new_cipher, front_region)?;
        tamper::refresh(new_secret, meta);
        meta.write(&vault.img)?;
    }
    Ok(())
}

// --- crash-window resume ----------------------------------------------------

/// Opportunistic, best-effort finish of an interrupted enable-headerOffset
/// scrub: if the front region still parses as a live LUKS2 header (i.e.
/// cryptsetup can still read it) *and* Meta already says `headerOffset`
/// is on (meaning that front copy is stale, not authoritative), the
/// commit already landed before the crash — scrubbing here is purely
/// finishing cosmetic cleanup, never a correctness fix. Deliberately
/// does NOT attempt to resume an interrupted *disable* direction's slot
/// scrub — that needs the master secret (to know which slot), which
/// isn't available at every call site this runs from (e.g. `open`
/// before a passphrase has been resolved for a lockout-protected vault).
/// Safe to call unconditionally and ignore the error; never fails loudly.
pub fn resume_scrub_if_pending(img: &Path) {
    let meta = Meta::read(img);
    if meta.header_offset != Some(true) {
        return;
    }
    if let Some(offset) = luks::data_offset_bytes(img) {
        let _ = scrub_front_region(img, offset);
    }
}

/// Physical ground truth for `header_offset`/`header_encryption`, used
/// by `tamper::reset_to_safe` — never trusts the stored booleans.
/// Structural checks first (front magic, or the length prefix of a
/// front-framed-encrypted header matching the one exact length a
/// minimized+encrypted header always has), falling back to `secret`
/// itself (already-verified at every real call site) to actually try
/// each candidate location. Falls back to `(false, false)` — "front,
/// plain" — if nothing can be proven, since pointing `open` at an
/// unproven location risks bricking the vault, which is strictly worse
/// than a possibly-stale-but-inert Meta value here (verify() runs again
/// on every open regardless).
pub fn ground_truth(img: &Path, secret: &[u8]) -> (bool, bool) {
    probe_location(img, secret).unwrap_or((false, false))
}

/// Location-independent version of `ground_truth`'s search: tries every
/// candidate header location (native front, front-framed-encrypted, room
/// slot plaintext, room slot encrypted) and returns the first one
/// `secret` actually opens, or `None` if it doesn't open any of them.
/// Unlike `ground_truth`, callers that need to tell "secret is wrong
/// everywhere" apart from "nothing provable, fall back to the safe
/// default" (which `ground_truth`'s `(false, false)` fallback collapses
/// into one case) use this directly -- `verify_current_secret`'s
/// meta-independent fallback, specifically, since when the *tampered*
/// field is `header_offset`/`header_encryption` itself, `meta` can't be
/// trusted to pick the one location to check.
fn probe_location(img: &Path, secret: &[u8]) -> Option<(bool, bool)> {
    if luks::test(img, secret) {
        return Some((false, false));
    }

    if let Some(salt) = room::read_salt(img) {
        let master = header::derive_master_secret(&[secret], &salt);

        // front-framed-encrypted?
        if let Ok(framed) = read_front_framed(img) {
            if framed.len() as u32 == FRAMED_ENCRYPTED_MINIMIZED_LEN {
                let key = header::derive_header_key(&master);
                if let Ok(plain) = decrypt_header(&key, &framed) {
                    if let Ok(t) = TempOutPath::reserve("hdr") {
                        if t.write_secure(&plain).is_ok() && luks::test_detached(t.path(), img, secret) {
                            return Some((false, true));
                        }
                    }
                }
            }
        }

        // relocated to a room slot -- plaintext or encrypted.
        let slot = header::derive_slot_index(&master, room::N_SLOTS as usize);
        if let Some(buf) = room::read_slot(img, slot as u64) {
            if let Ok(data) = unframe(&buf) {
                if let Ok(t) = TempOutPath::reserve("hdr") {
                    if t.write_secure(&data).is_ok() && luks::test_detached(t.path(), img, secret) {
                        return Some((true, false));
                    }
                }
                let key = header::derive_header_key(&master);
                if let Ok(plain) = decrypt_header(&key, &data) {
                    if let Ok(t) = TempOutPath::reserve("hdr") {
                        if t.write_secure(&plain).is_ok() && luks::test_detached(t.path(), img, secret) {
                            return Some((true, true));
                        }
                    }
                }
            }
        }
    }

    None
}

#[cfg(test)]
mod migration_tests {
    use super::*;
    use crate::config::Strength;

    /// Real end-to-end proof (live `cryptsetup`, not mocked) that
    /// `migrate_room_if_needed` correctly relocates a still-live v1-layout
    /// room slot to its v2 address and preserves the vault's payload
    /// throughout -- built by hand-crafting a v1 room (real `cas` never
    /// produces one anymore) so this test doesn't depend on a historical
    /// vault existing. Marked `#[ignore]`, same reasoning as
    /// `luks::header_offset_tests`. Run with `cargo test --bin cas --
    /// --ignored migration_tests`.
    #[test]
    #[ignore]
    fn v1_room_migrates_to_v2_and_preserves_payload() {
        let dir = std::env::temp_dir().join("cas-room-migration-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let vault = Vault {
            name: "migtest".to_string(),
            img: dir.join("migtest.img"),
            mnt: dir.join("migtest-mnt"),
            mapper: "cas_test_room_migration".to_string(),
        };
        std::fs::File::create(&vault.img).unwrap();
        crate::proc::run("truncate", &["-s", "64M", vault.img.to_str().unwrap()]).unwrap();
        let secret = b"migration-test-pass".to_vec();
        luks::format_vault_ex(&vault.img, &secret, Strength::Light, false).unwrap();

        // Provision a room, then hand-roll it back down to v1 layout:
        // write the same minimized header bytes into the *v1*-addressed
        // slot instead of the (real, current) v2 one, and stamp the
        // version byte back to 1 -- exactly what a room provisioned by
        // cas <=1.12.4 would look like today.
        Meta::strip(&vault.img).unwrap();
        let salt = room::ensure_provisioned(&vault.img).unwrap();
        let master = header::derive_master_secret(&[&secret], &salt);

        let offset_bytes = luks::data_offset_bytes(&vault.img).unwrap();
        let sector_size = luks::sector_size_bytes(&vault.img).unwrap();
        let vk = luks::dump_volume_key(&vault.img, &secret).unwrap();
        // Built by hand at v1's own (smaller, pre-integrity) 252k
        // keyslots-size, not via `format_minimized_detached_header` --
        // that function always requests today's bigger 512k now, which
        // wouldn't fit in a v1-sized slot, so it can't stand in for what
        // a real v1-era header actually looked like.
        let minihdr = dir.join("minihdr.img");
        let offset_sectors = (offset_bytes / 512).to_string();
        let sector_size_str = sector_size.to_string();
        crate::proc::run_with_stdin(
            "cryptsetup",
            &[
                "luksFormat", "--batch-mode", "--type", "luks2",
                "--header", minihdr.to_str().unwrap(),
                "--luks2-metadata-size", "16k",
                "--luks2-keyslots-size", "252k",
                "--offset", &offset_sectors,
                "--sector-size", &sector_size_str,
                "--volume-key-file", vk.path().to_str().unwrap(),
                "--pbkdf", "argon2id",
                "--pbkdf-force-iterations", Strength::Light.iterations(),
                vault.img.to_str().unwrap(),
                "--key-file", "-",
            ],
            &secret,
        ).unwrap();
        let plain_bytes = std::fs::read(&minihdr).unwrap();

        let v1_slot = header::derive_slot_index(&master, room::V1_N_SLOTS as usize) as u64;
        room::write_slot_v1_for_test(&vault.img, v1_slot, &frame(&plain_bytes)).unwrap();
        room::set_room_version(&vault.img, 1).unwrap();

        let mut meta = Meta::default();
        meta.header_room = Some(true);
        meta.header_offset = Some(true);
        meta.write(&vault.img).unwrap();

        assert_eq!(room::room_version(&vault.img), Some(1), "hand-crafted room must start at v1");

        // Real payload checksum before migration, via the v1-addressed
        // slot -- the actual proof migration doesn't alter content.
        let staged_v1 = TempOutPath::reserve("hdr").unwrap();
        staged_v1.write_secure(&plain_bytes).unwrap();
        assert!(luks::test_detached(staged_v1.path(), &vault.img, &secret), "v1-slot header must open before migration");

        let ctx = Ctx::default();
        migrate_room_if_needed(&ctx, &vault, &meta, &secret).expect("migration must succeed");

        assert_eq!(room::room_version(&vault.img), Some(2), "room must be stamped v2 after migration");
        let v2_slot = header::derive_slot_index(&master, room::N_SLOTS as usize) as u64;
        let relocated = room::read_slot(&vault.img, v2_slot).expect("v2 slot must be readable after migration");
        let relocated_unframed = unframe(&relocated).unwrap();
        assert_eq!(relocated_unframed, plain_bytes, "relocated bytes must be byte-identical to the original v1 slot's content");

        let staged_v2 = TempOutPath::reserve("hdr").unwrap();
        staged_v2.write_secure(&relocated_unframed).unwrap();
        assert!(luks::test_detached(staged_v2.path(), &vault.img, &secret), "relocated v2-slot header must still open the same payload");

        // Old v1 slot must be scrubbed post-migration (different content
        // now, since it's fresh random filler).
        let old_slot_now = room::read_slot_v1(&vault.img, v1_slot).unwrap();
        assert_ne!(unframe(&old_slot_now).unwrap_or_default(), plain_bytes, "old v1 slot must be scrubbed after a successful migration");
    }
}
