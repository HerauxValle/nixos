// &desc: "Raw fs-level provisioning/read/write for the 32 MiB header-hiding 'room' -- [LUKS2 container][32 MiB room][JSON trailer]. No cryptsetup calls here at all: this only knows how to find the room via meta::trailer_start, lay out its fixed-size candidate slots, and read/write raw bytes. Slot picking (which index) and header-content crypto live in header/mod.rs; enable/disable orchestration lives in header/relocate.rs."
use std::fs::OpenOptions;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

use rand::RngCore;

/// Total reserved room size, fixed per the design -- see docs/metadata-format.md.
pub const ROOM_SIZE: u64 = 32 * 1024 * 1024;

/// `[0, ROOM_HEADER_LEN)` — room header: magic, version, 32-byte salt,
/// rest reserved/random filler.
pub const ROOM_HEADER_LEN: u64 = 4096;

pub const ROOM_MAGIC: &[u8; 8] = b"CASHDR01";
/// Bumped 1 -> 2 when `SLOT_SIZE` grew to fit an integrity-formatted
/// header (see `SLOT_SIZE`'s doc comment) -- `room_version`/
/// `header::migrate` use this byte to tell an old-layout room (slot
/// addressing based on `V1_SLOT_SIZE`/`V1_N_SLOTS`) apart from a
/// current one, so a room provisioned by an older `cas` build doesn't
/// get silently misaddressed by code that now assumes the bigger size.
pub const ROOM_VERSION: u8 = 2;
const SALT_LEN: usize = 32;

/// Version 1's slot size (cas <=1.12.4, before dm-integrity support was
/// added to `headerOffset`/`headerEncryption`) -- 290,816 measured bytes
/// for a *plain* minimized header, 384 KiB slot. Kept only so
/// `header::migrate` can locate and relocate a still-live v1 slot's
/// bytes to their new v2 address; no current code ever writes at this
/// size.
pub const V1_SLOT_SIZE: u64 = 384 * 1024;
/// Version 1's slot count: `(ROOM_SIZE - ROOM_HEADER_LEN) / V1_SLOT_SIZE` = 85.
pub const V1_N_SLOTS: u64 = (ROOM_SIZE - ROOM_HEADER_LEN) / V1_SLOT_SIZE;

/// Per-slot size. A dm-integrity-protected container's volume key is 96
/// bytes (a plain AES-256-XTS + HMAC-SHA256 key, vs. 64 bytes without
/// integrity), which needs a much bigger LUKS2 keyslots area to fit a
/// real Argon2id keyslot -- measured live 2026-08-17 against cryptsetup
/// 2.8.6: `--luks2-keyslots-size 384k` is the smallest 4k-aligned size
/// that still succeeds (368k fails with "No space for new keyslot"),
/// giving a 425,984-byte minimized+integrity header on-disk (426,012
/// framed+encrypted). `header/relocate.rs` always requests a fixed
/// `512k` keyslots-size regardless of whether the source container
/// actually has integrity, to keep one constant here in sync with one
/// cryptsetup flag there instead of two conditional sizes; 768 KiB
/// gives ~35% headroom above that 512k-keyslots real-world floor (mirrors
/// the same headroom ratio v1's 384 KiB gave over its 290,816-byte floor)
/// for future growth (a bigger cipher/integrity combination, additional
/// PBKDF parameters, etc.) without needing another slot-size bump.
pub const SLOT_SIZE: u64 = 768 * 1024;

/// Number of candidate slots that fit in the room after its header:
/// `(ROOM_SIZE - ROOM_HEADER_LEN) / SLOT_SIZE` = 42.
pub const N_SLOTS: u64 = (ROOM_SIZE - ROOM_HEADER_LEN) / SLOT_SIZE;

/// Room version for `fileIntegrity`-compatible vaults -- stores the
/// vault's real, full-size header verbatim (copied, never rebuilt via
/// `luksFormat`) instead of a minimized one, since any fresh
/// `luksFormat --integrity` call against the container corrupts its
/// payload regardless of file-size tricks (confirmed live 2026-08-17 --
/// see `header::relocate`'s doc comments). Slot size/count for this
/// flavor aren't fixed constants like v1/v2's -- the room's *total*
/// size varies per vault (`ROOM_HEADER_LEN + n_slots * INTEGRITY_SLOT_SIZE`,
/// `n_slots` chosen at enable time and stored in `Meta.header_room_slots`)
/// -- so every v3 function below takes `n_slots` explicitly rather than
/// reading a global constant.
pub const ROOM_VERSION_INTEGRITY: u8 = 3;

/// Per-slot size for a v3 room -- fixed constant with headroom above
/// the measured real header size (confirmed live 2026-08-17: 16 MiB via
/// `luksDump`'s `offset:` field, same value with or without integrity,
/// for this cryptsetup build -- matches this codebase's existing
/// precedent of a measured-plus-headroom hardcoded constant rather than
/// a per-vault-derived size, e.g. `luks::front_region_len`'s 16 MiB
/// fallback). 20 MiB gives ~25% headroom.
pub const INTEGRITY_SLOT_SIZE: u64 = 20 * 1024 * 1024;

/// Default slot count for a v3 room, before any explicit `--slots N` --
/// deterministic by vault size (mirrors `commands::create`'s
/// `INTEGRITY_PROMPT_THRESHOLD_MB` pattern), not a security choice: see
/// `INTEGRITY_SLOT_SIZE`'s and `header::relocate`'s doc comments for why
/// slot count past a handful buys no additional hiding strength, only
/// disk overhead. Vaults at or above this size default to 4 slots
/// (~80 MiB room); smaller ones default to 2 (~40 MiB).
pub const INTEGRITY_DEFAULT_SLOTS_THRESHOLD_MB: u64 = 1024;
pub const INTEGRITY_DEFAULT_SLOTS_LARGE: u32 = 4;
pub const INTEGRITY_DEFAULT_SLOTS_SMALL: u32 = 2;

/// Byte offset (from the start of `vault.img`) where a v3 room lives --
/// right after the fixed-size area cryptsetup's own default LUKS2
/// metadata/keyslots area occupies (measured 16 MiB, same value this
/// codebase's other 16 MiB fallbacks assume, e.g. `luks::front_region_len`).
/// Free real estate between here and `config::LUKS_DATA_OFFSET_MB`
/// (128) exists on every vault formatted after that constant landed,
/// specifically reserved for this -- see `config::LUKS_DATA_OFFSET_MB`'s
/// doc comment. Fixed, not derived per-vault: `luksFormat` never
/// receives a custom `--luks2-metadata-size`/`--luks2-keyslots-size` for
/// a *vault's own* format (only for a relocated/rebuilt detached
/// header), so every vault this codebase creates has the exact same
/// 16 MiB metadata footprint regardless of its overall size.
pub const V3_ROOM_OFFSET_MB: u64 = 16;

/// Total space available to a v3 room -- the gap between
/// `V3_ROOM_OFFSET_MB` and `config::LUKS_DATA_OFFSET_MB`. Unlike v1/v2's
/// `ROOM_SIZE` (appended after the payload, so effectively unbounded),
/// this is a hard ceiling: the room lives *inside* the vault's own fixed
/// offset reservation now, not a separate file that can grow freely.
pub const V3_ROOM_AVAILABLE_BYTES: u64 = (crate::config::LUKS_DATA_OFFSET_MB - V3_ROOM_OFFSET_MB) * 1024 * 1024;

/// Hard ceiling on `--slots N`/`slots <N>` for a v3 room -- how many
/// `INTEGRITY_SLOT_SIZE` slots actually fit in `V3_ROOM_AVAILABLE_BYTES`
/// after the room header. Unlike the old sibling-file design (where more
/// slots just meant a bigger separate file), this is a real, enforced
/// maximum now -- `commands::settings::security::header_offset::run`
/// refuses a request above it outright rather than merely advising
/// against it.
pub const INTEGRITY_MAX_SLOTS: u32 = ((V3_ROOM_AVAILABLE_BYTES - ROOM_HEADER_LEN) / INTEGRITY_SLOT_SIZE) as u32;

/// `--slots N`/`slots <N>` above this (but still <= `INTEGRITY_MAX_SLOTS`)
/// prints a one-time advisory that more slots past this point are pure
/// disk overhead, not added security -- see `INTEGRITY_SLOT_SIZE`'s doc
/// comment. Never blocks by itself; `INTEGRITY_MAX_SLOTS` is the actual
/// hard limit.
pub const INTEGRITY_SLOTS_ADVISORY_THRESHOLD: u32 = INTEGRITY_DEFAULT_SLOTS_LARGE;

pub fn integrity_default_slots(vault_size_mb: u64) -> u32 {
    if vault_size_mb >= INTEGRITY_DEFAULT_SLOTS_THRESHOLD_MB {
        INTEGRITY_DEFAULT_SLOTS_LARGE
    } else {
        INTEGRITY_DEFAULT_SLOTS_SMALL
    }
}

fn v3_room_total_size(n_slots: u64) -> u64 {
    ROOM_HEADER_LEN + n_slots * INTEGRITY_SLOT_SIZE
}

/// Byte offset in `vault.img` where a v3 room starts -- always
/// `V3_ROOM_OFFSET_MB`, a fixed constant, never derived per-vault. This
/// deliberately does NOT append to or otherwise change the image's own
/// length: everything a v3 room reads or writes sits strictly between
/// the LUKS2 metadata area and `config::LUKS_DATA_OFFSET_MB`'s data
/// segment, both fixed at format time, so the image's "till end of
/// device" dynamic size calculation (what a plain `luksFormat`/`open`
/// keys off of) never changes -- this is exactly the property the
/// now-removed `.hroom` sibling-file design existed to guarantee a
/// different way; living inside the reserved offset gets the same
/// guarantee for free, without a second file on disk. See
/// `config::LUKS_DATA_OFFSET_MB`'s doc comment for why the gap exists,
/// and `V3_ROOM_AVAILABLE_BYTES` for how big it is.
pub fn v3_room_start() -> u64 {
    V3_ROOM_OFFSET_MB * 1024 * 1024
}

/// Byte offset of `Vault::lock_exclusive`'s advisory record-lock range --
/// the last 4 KiB of the reserved offset gap, immediately before
/// `config::LUKS_DATA_OFFSET_MB`'s LUKS2 payload begins. Never written by
/// this module: even a fully-packed room (`INTEGRITY_MAX_SLOTS` slots)
/// only reaches `ROOM_HEADER_LEN + INTEGRITY_MAX_SLOTS * INTEGRITY_SLOT_SIZE`
/// bytes past `v3_room_start()`, which by `INTEGRITY_MAX_SLOTS`'s own
/// construction is always comfortably under `V3_ROOM_AVAILABLE_BYTES` --
/// there's slack left over from truncating division, so this offset is
/// unreachable by room writes regardless of slot count, and is fixed
/// (not slot-count-derived) so it needs no coordination with room state
/// at all. Also below `LUKS_DATA_OFFSET_MB`, so it's never inside the
/// LUKS2 payload dm-integrity's tag layout is computed against either.
pub const LOCK_OFFSET: u64 = crate::config::LUKS_DATA_OFFSET_MB * 1024 * 1024 - 4096;

/// v3 equivalent of `read_salt`. `n_slots` isn't needed to locate the
/// room (its start is a fixed offset, not something the caller derives),
/// but every call site already threads it through for the slot
/// read/write bounds checks below, so the signature stays consistent.
pub fn v3_read_salt(img: &Path, _n_slots: u64) -> Option<[u8; SALT_LEN]> {
    let mut f = OpenOptions::new().read(true).open(img).ok()?;
    let mut header = [0u8; ROOM_HEADER_LEN as usize];
    f.seek(SeekFrom::Start(v3_room_start())).ok()?;
    f.read_exact(&mut header).ok()?;
    if &header[0..8] != ROOM_MAGIC {
        return None;
    }
    let mut salt = [0u8; SALT_LEN];
    salt.copy_from_slice(&header[9..9 + SALT_LEN]);
    Some(salt)
}

/// v3 equivalent of `ensure_provisioned`.
pub fn v3_ensure_provisioned(img: &Path, n_slots: u64) -> std::io::Result<[u8; SALT_LEN]> {
    if let Some(salt) = v3_read_salt(img, n_slots) {
        return Ok(salt);
    }
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    v3_write_fresh_room(img, n_slots, &salt)?;
    Ok(salt)
}

/// Like `v3_ensure_provisioned`, but with an explicit salt instead of
/// minting a random one -- used by `header::relocate`'s `slots <N>`
/// (changing an existing v3 room's slot count) to reprovision a
/// differently-sized room *at the same salt*, so the header-content
/// encryption key (`header::derive_header_key(master)`, itself a
/// function of this salt) doesn't change -- only the slot count and
/// therefore the derived slot index does. Caller is responsible for
/// having already removed any prior room (`v3_remove_room`) -- this
/// always writes a fresh file, never reuses existing bytes.
pub fn v3_ensure_provisioned_with_salt(img: &Path, n_slots: u64, salt: &[u8; SALT_LEN]) -> std::io::Result<()> {
    v3_write_fresh_room(img, n_slots, salt)
}

fn v3_write_fresh_room(img: &Path, n_slots: u64, salt: &[u8; SALT_LEN]) -> std::io::Result<()> {
    if n_slots > INTEGRITY_MAX_SLOTS as u64 {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, format!("{n_slots} slots exceeds the {INTEGRITY_MAX_SLOTS}-slot ceiling that fits in the vault's reserved offset region")));
    }
    let mut header = vec![0u8; ROOM_HEADER_LEN as usize];
    header[0..8].copy_from_slice(ROOM_MAGIC);
    header[8] = ROOM_VERSION_INTEGRITY;
    header[9..9 + SALT_LEN].copy_from_slice(salt);

    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(v3_room_start()))?;
    f.write_all(&header)?;

    let mut rng = rand::thread_rng();
    let mut buf = vec![0u8; 1024 * 1024];
    let mut remaining = v3_room_total_size(n_slots) - ROOM_HEADER_LEN;
    while remaining > 0 {
        let chunk = remaining.min(buf.len() as u64) as usize;
        rng.fill_bytes(&mut buf[..chunk]);
        f.write_all(&buf[..chunk])?;
        remaining -= chunk as u64;
    }
    f.flush()
}

/// Scrubs the v3 room's header + every slot with fresh random filler,
/// in place. Used by `slots <N>` right before provisioning a fresh room
/// at the new size in the same fixed location -- unlike the old
/// sibling-file design (where this deleted a whole file), there's no
/// file to remove: the room always occupies the same fixed offset
/// region, only its logical slot count changes.
pub fn v3_remove_room(img: &Path, n_slots: u64) -> std::io::Result<()> {
    let mut f = match OpenOptions::new().write(true).open(img) {
        Ok(f) => f,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e),
    };
    f.seek(SeekFrom::Start(v3_room_start()))?;
    let mut rng = rand::thread_rng();
    let mut buf = vec![0u8; 1024 * 1024];
    let mut remaining = v3_room_total_size(n_slots.max(1));
    while remaining > 0 {
        let chunk = remaining.min(buf.len() as u64) as usize;
        rng.fill_bytes(&mut buf[..chunk]);
        f.write_all(&buf[..chunk])?;
        remaining -= chunk as u64;
    }
    f.flush()
}

/// v3 equivalent of `read_slot` -- `data.len()` need not match
/// `INTEGRITY_SLOT_SIZE` exactly (a real header's exact byte size can
/// vary slightly by cryptsetup build), so the caller gets the full
/// slot back and locates its own framed payload within it (same
/// `frame`/`unframe` convention `relocate.rs` already uses elsewhere).
pub fn v3_read_slot(img: &Path, n_slots: u64, index: u64) -> Option<Vec<u8>> {
    if index >= n_slots {
        return None;
    }
    let mut f = OpenOptions::new().read(true).open(img).ok()?;
    let mut buf = vec![0u8; INTEGRITY_SLOT_SIZE as usize];
    f.seek(SeekFrom::Start(v3_room_start() + ROOM_HEADER_LEN + index * INTEGRITY_SLOT_SIZE)).ok()?;
    f.read_exact(&mut buf).ok()?;
    Some(buf)
}

/// v3 equivalent of `write_slot`.
pub fn v3_write_slot(img: &Path, n_slots: u64, index: u64, data: &[u8]) -> std::io::Result<()> {
    if data.len() as u64 > INTEGRITY_SLOT_SIZE {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot payload exceeds INTEGRITY_SLOT_SIZE"));
    }
    if index >= n_slots {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot index out of range"));
    }

    let mut padded = vec![0u8; INTEGRITY_SLOT_SIZE as usize];
    padded[..data.len()].copy_from_slice(data);
    if data.len() < INTEGRITY_SLOT_SIZE as usize {
        rand::thread_rng().fill_bytes(&mut padded[data.len()..]);
    }

    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(v3_room_start() + ROOM_HEADER_LEN + index * INTEGRITY_SLOT_SIZE))?;
    f.write_all(&padded)?;
    f.flush()
}

/// v3 equivalent of `scrub_slot`.
pub fn v3_scrub_slot(img: &Path, n_slots: u64, index: u64) -> std::io::Result<()> {
    let mut filler = vec![0u8; INTEGRITY_SLOT_SIZE as usize];
    rand::thread_rng().fill_bytes(&mut filler);
    if index >= n_slots {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot index out of range"));
    }
    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(v3_room_start() + ROOM_HEADER_LEN + index * INTEGRITY_SLOT_SIZE))?;
    f.write_all(&filler)?;
    f.flush()
}

/// Where slot `index`'s bytes start, relative to the room's own start
/// (not the file's) -- parameterized over slot size so the v1 versioned
/// helpers below can reuse it against the old layout.
fn slot_offset_sized(index: u64, slot_size: u64) -> u64 {
    ROOM_HEADER_LEN + index * slot_size
}

/// Absolute file offset where the room starts (or would start).
/// Immediately before wherever `meta::trailer_start` currently finds the
/// trailer when one's present -- but `ensure_provisioned` always runs
/// between `Meta::strip` and `Meta::write` (see its doc comment), i.e.
/// exactly when there's *no* trailer to locate, so this falls back to
/// "32 MiB before EOF" in that case. Both branches land on the same
/// physical offset in practice, since `strip` truncates the file down
/// to precisely where the room (or bare container, if none provisioned
/// yet) ends.
fn room_start(img: &Path) -> Option<u64> {
    let candidate = match crate::meta::trailer_start(img) {
        Some(trailer_start) => trailer_start,
        None => std::fs::metadata(img).ok()?.len(),
    };
    candidate.checked_sub(ROOM_SIZE)
}

/// `Some(salt)` if a room with valid magic is present at the expected
/// location; `None` otherwise (no trailer, file too short, or magic
/// doesn't match -- the last case covers both "never provisioned" and
/// "this offset isn't actually a room" e.g. right after a resize that
/// hasn't reprovisioned yet).
pub fn read_salt(img: &Path) -> Option<[u8; SALT_LEN]> {
    let start = room_start(img)?;
    let mut f = OpenOptions::new().read(true).open(img).ok()?;
    let mut header = [0u8; ROOM_HEADER_LEN as usize];
    f.seek(SeekFrom::Start(start)).ok()?;
    f.read_exact(&mut header).ok()?;
    if &header[0..8] != ROOM_MAGIC {
        return None;
    }
    let mut salt = [0u8; SALT_LEN];
    salt.copy_from_slice(&header[9..9 + SALT_LEN]);
    Some(salt)
}

/// The container's true payload boundary -- where the room starts if
/// one's provisioned, otherwise the current file length. `Meta::strip`
/// is assumed to have already removed the trailer (every caller in
/// `relocate.rs` guarantees this), so the only thing that can be sitting
/// after the real LUKS2 container is the room itself.
///
/// Used by `header::relocate`'s `with_room_hidden` to temporarily
/// truncate the room away before any `luksFormat --integrity` call
/// against `img` -- confirmed live 2026-08-17: cryptsetup (re)initializes
/// dm-integrity's per-sector tag/journal structures out to *however big
/// the underlying file currently is* (the container's data segment is
/// dynamic/"till end of device", never given an explicit fixed size),
/// so if the room is already appended when a new detached header gets
/// built, that init pass silently overwrites straight through it -- not
/// on open, only on a fresh `luksFormat`, and only ever confirmed with
/// `--integrity` involved.
///
/// Only used for v1/v2 (non-integrity) rooms, which are safe to append
/// to the image because a plain LUKS2 payload has no size-dependent
/// internal structure. A v3 room lives at a fixed offset inside the
/// image's own reserved header-offset region instead
/// (`v3_room_start`) for exactly the reason this doesn't generalize to
/// integrity-protected containers -- see that function's doc comment
/// for the full story.
pub fn container_boundary(img: &Path) -> u64 {
    let full_len = std::fs::metadata(img).map(|m| m.len()).unwrap_or(0);
    if read_salt(img).is_some() {
        if let Some(start) = room_start(img) {
            return start;
        }
    }
    full_len
}

/// The room layout version currently stamped in the header, or `None` if
/// there's no room at all -- lets `header::migrate` tell a v1 room (still
/// possibly holding live content addressed by `V1_SLOT_SIZE`/
/// `V1_N_SLOTS`) apart from a current-layout one.
pub fn room_version(img: &Path) -> Option<u8> {
    let start = room_start(img)?;
    let mut f = OpenOptions::new().read(true).open(img).ok()?;
    let mut header = [0u8; ROOM_HEADER_LEN as usize];
    f.seek(SeekFrom::Start(start)).ok()?;
    f.read_exact(&mut header).ok()?;
    if &header[0..8] != ROOM_MAGIC {
        return None;
    }
    Some(header[8])
}

/// Stamp the room header's version byte in place -- the sole "commit"
/// step of a room-layout migration (see `header::migrate`): a crash
/// before this leaves the old version number still authoritative (old
/// layout still fully readable), a crash after leaves the new version
/// authoritative with its content already verified and in place. Never
/// touches the salt or anything past byte 9.
pub fn set_room_version(img: &Path, version: u8) -> std::io::Result<()> {
    let start = room_start(img).ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "room not provisioned"))?;
    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(start + 8))?;
    f.write_all(&[version])?;
    f.flush()
}

/// Idempotent room provisioning. Must be called on a file that's
/// already had `Meta::strip`'d its trailer off (so the room lands
/// immediately at the container's real end) -- the caller is
/// responsible for calling `Meta::write` afterward to reattach the
/// trailer on top, same "strip -> mutate -> write" shape every other
/// raw-byte operation in this codebase uses. Reuses an existing room
/// (same salt) if one's already there rather than blindly re-appending
/// -- covers resuming after a provision attempt that was interrupted
/// after the room bytes landed but before `Meta.header_room` was
/// committed.
///
/// Room content is fresh CSPRNG bytes, not zeros -- a block of zeros
/// sitting between two structured regions is itself a signature; random
/// filler is indistinguishable from an unused candidate slot.
pub fn ensure_provisioned(img: &Path) -> std::io::Result<[u8; SALT_LEN]> {
    if let Some(salt) = read_salt(img) {
        return Ok(salt);
    }

    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);

    let mut header = vec![0u8; ROOM_HEADER_LEN as usize];
    header[0..8].copy_from_slice(ROOM_MAGIC);
    header[8] = ROOM_VERSION;
    header[9..9 + SALT_LEN].copy_from_slice(&salt);
    // Bytes after the salt (reserved) are left as zero, not random --
    // deliberately: they're inside a region already unambiguously
    // identified as "cas room header" by the magic right before it, so
    // there's no deniability left to buy by randomizing them, and
    // leaving them zero keeps the reserved region trivially
    // distinguishable from real content for any future format bump.

    let mut f = OpenOptions::new().write(true).append(false).open(img)?;
    f.seek(SeekFrom::End(0))?;
    f.write_all(&header)?;

    let mut rng = rand::thread_rng();
    let mut buf = vec![0u8; 1024 * 1024];
    let mut remaining = ROOM_SIZE - ROOM_HEADER_LEN;
    while remaining > 0 {
        let chunk = remaining.min(buf.len() as u64) as usize;
        rng.fill_bytes(&mut buf[..chunk]);
        f.write_all(&buf[..chunk])?;
        remaining -= chunk as u64;
    }
    f.flush()?;
    Ok(salt)
}

/// Read slot `index`'s raw bytes (always exactly `slot_size`). `None` if
/// there's no room, or `index >= n_slots`. Parameterized so
/// `header::migrate` can read a still-live v1 slot with
/// `(V1_SLOT_SIZE, V1_N_SLOTS)`; `read_slot` below is the normal current-
/// layout entry point every other caller uses.
fn read_slot_sized(img: &Path, index: u64, slot_size: u64, n_slots: u64) -> Option<Vec<u8>> {
    if index >= n_slots {
        return None;
    }
    let start = room_start(img)?;
    let mut f = OpenOptions::new().read(true).open(img).ok()?;
    let mut buf = vec![0u8; slot_size as usize];
    f.seek(SeekFrom::Start(start + slot_offset_sized(index, slot_size))).ok()?;
    f.read_exact(&mut buf).ok()?;
    Some(buf)
}

/// Write `data` into slot `index`, padded with fresh CSPRNG filler up to
/// `slot_size` if shorter. Errors if `data` doesn't fit or the room
/// isn't provisioned. Caller (`relocate.rs`) is responsible for the
/// verify-before-mutate ordering around this -- this function itself
/// just performs the raw write, no safety judgment. Parameterized for
/// the same reason as `read_slot_sized`.
fn write_slot_sized(img: &Path, index: u64, data: &[u8], slot_size: u64, n_slots: u64) -> std::io::Result<()> {
    if data.len() as u64 > slot_size {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot payload exceeds slot size"));
    }
    if index >= n_slots {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot index out of range"));
    }
    let start = room_start(img).ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "room not provisioned"))?;

    let mut padded = vec![0u8; slot_size as usize];
    padded[..data.len()].copy_from_slice(data);
    if data.len() < slot_size as usize {
        rand::thread_rng().fill_bytes(&mut padded[data.len()..]);
    }

    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(start + slot_offset_sized(index, slot_size)))?;
    f.write_all(&padded)?;
    f.flush()
}

pub fn read_slot(img: &Path, index: u64) -> Option<Vec<u8>> {
    read_slot_sized(img, index, SLOT_SIZE, N_SLOTS)
}

pub fn write_slot(img: &Path, index: u64, data: &[u8]) -> std::io::Result<()> {
    write_slot_sized(img, index, data, SLOT_SIZE, N_SLOTS)
}

/// v1-layout equivalent of `read_slot` -- only ever used by
/// `header::migrate` to pull a still-live v1 slot's bytes out before
/// relocating them to their v2 address.
pub fn read_slot_v1(img: &Path, index: u64) -> Option<Vec<u8>> {
    read_slot_sized(img, index, V1_SLOT_SIZE, V1_N_SLOTS)
}

/// v1-layout equivalent of `write_slot` -- no production code ever
/// writes at v1 size (only `read_slot_v1`/`scrub_slot_v1` do, during
/// migration), so this only exists for `header::relocate`'s migration
/// test to hand-craft a v1 room without a real historical vault.
#[cfg(test)]
pub fn write_slot_v1_for_test(img: &Path, index: u64, data: &[u8]) -> std::io::Result<()> {
    write_slot_sized(img, index, data, V1_SLOT_SIZE, V1_N_SLOTS)
}

/// v1-layout equivalent of `scrub_slot` -- used by `header::migrate` to
/// wipe the old slot's bytes once its content has been verified at its
/// new v2 address and the room version has already been committed.
pub fn scrub_slot_v1(img: &Path, index: u64) -> std::io::Result<()> {
    let mut filler = vec![0u8; V1_SLOT_SIZE as usize];
    rand::thread_rng().fill_bytes(&mut filler);
    write_raw_slot_sized(img, index, &filler, V1_SLOT_SIZE, V1_N_SLOTS)
}

/// Overwrite slot `index` with fresh random filler -- used to scrub a
/// slot's content after `relocate.rs` has already committed `Meta` to
/// point elsewhere (see relocate.rs's crash-safety doc comment: this is
/// always called strictly after commit, never before).
pub fn scrub_slot(img: &Path, index: u64) -> std::io::Result<()> {
    let mut filler = vec![0u8; SLOT_SIZE as usize];
    rand::thread_rng().fill_bytes(&mut filler);
    write_raw_slot_sized(img, index, &filler, SLOT_SIZE, N_SLOTS)
}

/// Like `write_slot_sized` but never pads (`data` must already be
/// exactly `slot_size`) -- internal helper for `scrub_slot`/`scrub_slot_v1`.
fn write_raw_slot_sized(img: &Path, index: u64, data: &[u8], slot_size: u64, n_slots: u64) -> std::io::Result<()> {
    debug_assert_eq!(data.len() as u64, slot_size);
    if index >= n_slots {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot index out of range"));
    }
    let start = room_start(img).ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "room not provisioned"))?;
    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(start + slot_offset_sized(index, slot_size)))?;
    f.write_all(data)?;
    f.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch_vault(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join("cas-room-test");
        let _ = std::fs::create_dir_all(&dir);
        let img = dir.join(name);
        let _ = std::fs::remove_file(&img);
        // Minimal fake "container": some bytes standing in for a LUKS2
        // container's front region -- room.rs never parses this, it
        // only cares about trailer_start, so a plain byte blob is
        // sufficient here (no real cryptsetup needed for this test).
        std::fs::write(&img, vec![0xABu8; 4 * 1024 * 1024]).unwrap();
        img
    }

    fn write_trailer(img: &std::path::Path) {
        let meta = crate::meta::Meta::default();
        meta.write(img).unwrap();
    }

    #[test]
    fn provision_then_reprovision_is_idempotent() {
        let img = scratch_vault("provision.img");
        write_trailer(&img);
        crate::meta::Meta::strip(&img).unwrap();
        let salt_a = ensure_provisioned(&img).unwrap();
        write_trailer(&img);

        crate::meta::Meta::strip(&img).unwrap();
        let salt_b = ensure_provisioned(&img).unwrap();
        assert_eq!(salt_a, salt_b, "re-provisioning must reuse the existing room, not mint a new salt");
        write_trailer(&img);
    }

    #[test]
    fn slot_round_trips_and_survives_trailer_rewrites() {
        let img = scratch_vault("slot.img");
        write_trailer(&img);
        crate::meta::Meta::strip(&img).unwrap();
        ensure_provisioned(&img).unwrap();
        write_trailer(&img);

        let payload = b"pretend-luks2-header-bytes".to_vec();
        write_slot(&img, 3, &payload).unwrap();
        let readback = read_slot(&img, 3).unwrap();
        assert_eq!(&readback[..payload.len()], &payload[..]);

        // Round-trip the trailer several times via normal strip/write --
        // this is exactly what every settings toggle's meta.write() does
        // -- and confirm the room (and this slot specifically) is
        // untouched afterward.
        for _ in 0..5 {
            let mut meta = crate::meta::Meta::read(&img);
            meta.zeroize = Some(!meta.zeroize.unwrap_or(true));
            meta.write(&img).unwrap();
        }

        let readback2 = read_slot(&img, 3).unwrap();
        assert_eq!(readback, readback2, "room slot bytes must survive repeated trailer strip/write round-trips unchanged");
    }

    #[test]
    fn scrub_changes_slot_bytes() {
        let img = scratch_vault("scrub.img");
        write_trailer(&img);
        crate::meta::Meta::strip(&img).unwrap();
        ensure_provisioned(&img).unwrap();
        write_trailer(&img);

        write_slot(&img, 7, b"secret-header-material").unwrap();
        let before = read_slot(&img, 7).unwrap();
        scrub_slot(&img, 7).unwrap();
        let after = read_slot(&img, 7).unwrap();
        assert_ne!(before, after);
    }

    #[test]
    fn slot_size_and_count_match_measured_constants() {
        // Guards against SLOT_SIZE/N_SLOTS silently drifting out of
        // sync with header/relocate.rs's cryptsetup flags -- see
        // SLOT_SIZE's doc comment for the measured numbers.
        assert_eq!(SLOT_SIZE, 768 * 1024);
        assert_eq!(N_SLOTS, 42);
        assert!(ROOM_HEADER_LEN + N_SLOTS * SLOT_SIZE <= ROOM_SIZE);
        assert_eq!(V1_SLOT_SIZE, 384 * 1024);
        assert_eq!(V1_N_SLOTS, 85);
        assert!(ROOM_HEADER_LEN + V1_N_SLOTS * V1_SLOT_SIZE <= ROOM_SIZE);
    }

    #[test]
    fn out_of_range_slot_rejected() {
        let img = scratch_vault("range.img");
        write_trailer(&img);
        crate::meta::Meta::strip(&img).unwrap();
        ensure_provisioned(&img).unwrap();
        write_trailer(&img);
        assert!(write_slot(&img, N_SLOTS, b"x").is_err());
        assert!(read_slot(&img, N_SLOTS).is_none());
    }
}
