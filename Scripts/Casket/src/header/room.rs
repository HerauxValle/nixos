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
const ROOM_VERSION: u8 = 1;
const SALT_LEN: usize = 32;

/// Per-slot size, measured live 2026-08-16 against cryptsetup 2.8.6: a
/// minimized single-active-keyslot LUKS2 header (`--luks2-metadata-size
/// 16k --luks2-keyslots-size 252k`, the smallest 4k-aligned keyslots-size
/// that still lets a real Argon2id keyslot fit) needs 16k*2 + 252k =
/// 290816 bytes on-disk. 384 KiB gives ~35% headroom above that measured
/// floor -- see header/relocate.rs's format call for the exact
/// cryptsetup flags this constant has to stay in sync with.
pub const SLOT_SIZE: u64 = 384 * 1024;

/// Number of candidate slots that fit in the room after its header:
/// `(ROOM_SIZE - ROOM_HEADER_LEN) / SLOT_SIZE` = 85.
pub const N_SLOTS: u64 = (ROOM_SIZE - ROOM_HEADER_LEN) / SLOT_SIZE;

/// Where slot `index`'s bytes start, relative to the room's own start
/// (not the file's).
fn slot_offset(index: u64) -> u64 {
    ROOM_HEADER_LEN + index * SLOT_SIZE
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

pub fn is_provisioned(img: &Path) -> bool {
    read_salt(img).is_some()
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

/// Read slot `index`'s raw bytes (always exactly `SLOT_SIZE`). `None` if
/// there's no room, or `index >= N_SLOTS`.
pub fn read_slot(img: &Path, index: u64) -> Option<Vec<u8>> {
    if index >= N_SLOTS {
        return None;
    }
    let start = room_start(img)?;
    let mut f = OpenOptions::new().read(true).open(img).ok()?;
    let mut buf = vec![0u8; SLOT_SIZE as usize];
    f.seek(SeekFrom::Start(start + slot_offset(index))).ok()?;
    f.read_exact(&mut buf).ok()?;
    Some(buf)
}

/// Write `data` into slot `index`, padded with fresh CSPRNG filler up to
/// `SLOT_SIZE` if shorter. Errors if `data` doesn't fit or the room
/// isn't provisioned. Caller (`relocate.rs`) is responsible for the
/// verify-before-mutate ordering around this -- this function itself
/// just performs the raw write, no safety judgment.
pub fn write_slot(img: &Path, index: u64, data: &[u8]) -> std::io::Result<()> {
    if data.len() as u64 > SLOT_SIZE {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot payload exceeds SLOT_SIZE"));
    }
    if index >= N_SLOTS {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot index out of range"));
    }
    let start = room_start(img).ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "room not provisioned"))?;

    let mut padded = vec![0u8; SLOT_SIZE as usize];
    padded[..data.len()].copy_from_slice(data);
    if data.len() < SLOT_SIZE as usize {
        rand::thread_rng().fill_bytes(&mut padded[data.len()..]);
    }

    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(start + slot_offset(index)))?;
    f.write_all(&padded)?;
    f.flush()
}

/// Overwrite slot `index` with fresh random filler -- used to scrub a
/// slot's content after `relocate.rs` has already committed `Meta` to
/// point elsewhere (see relocate.rs's crash-safety doc comment: this is
/// always called strictly after commit, never before).
pub fn scrub_slot(img: &Path, index: u64) -> std::io::Result<()> {
    let mut filler = vec![0u8; SLOT_SIZE as usize];
    rand::thread_rng().fill_bytes(&mut filler);
    write_raw_slot(img, index, &filler)
}

/// Like `write_slot` but never pads (`data` must already be exactly
/// `SLOT_SIZE`) -- internal helper for `scrub_slot`.
fn write_raw_slot(img: &Path, index: u64, data: &[u8]) -> std::io::Result<()> {
    debug_assert_eq!(data.len() as u64, SLOT_SIZE);
    if index >= N_SLOTS {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "slot index out of range"));
    }
    let start = room_start(img).ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "room not provisioned"))?;
    let mut f = OpenOptions::new().write(true).open(img)?;
    f.seek(SeekFrom::Start(start + slot_offset(index)))?;
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
        assert_eq!(SLOT_SIZE, 384 * 1024);
        assert_eq!(N_SLOTS, 85);
        assert!(ROOM_HEADER_LEN + N_SLOTS * SLOT_SIZE <= ROOM_SIZE);
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
