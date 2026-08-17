// &desc: "Pure KDF logic for the headerOffset/headerEncryption header-hiding features: Argon2id(salt, framed IKM) -> master secret, then HKDF-Expand(master_secret, info=<purpose>) for independent per-purpose subkeys (slot selection, header content encryption). No I/O here at all -- room/file access lives in room.rs, cryptsetup calls in relocate.rs -- so this half is fully unit-testable without touching disk or a real vault."
pub mod relocate;
pub mod room;

use argon2::{Algorithm, Argon2, Params, Version};
use hkdf::Hkdf;
use sha2::Sha256;

/// Argon2id cost params for the master-secret derivation. This runs
/// once per open of a headerOffset/headerEncryption vault, alongside
/// (not instead of) cryptsetup's own LUKS2 Argon2id pass -- kept modest
/// (well below the vault's own `Strength` presets) since it's pure
/// overhead added to every open, not the primary line of defense (that's
/// still the LUKS2 keyslot KDF). 19 MiB / 2 iterations / 1 lane mirrors
/// the RFC 9106 "low-memory" recommended preset.
const ARGON2_MEM_KIB: u32 = 19 * 1024;
const ARGON2_ITERATIONS: u32 = 2;
const ARGON2_LANES: u32 = 1;
const MASTER_SECRET_LEN: usize = 32;

pub const INFO_SLOT: &[u8] = b"cas:header-slot";
pub const INFO_KEY: &[u8] = b"cas:header-key";

/// Frame each IKM part with a 4-byte big-endian length prefix before
/// concatenating -- so `[passphrase][keyfile]` and a differently-split
/// `[passphra][se+keyfile]` can never collide, and a future third part
/// (a planned hardware-identifier secret) is a pure append with no
/// reframing of the existing parts.
fn frame_ikm(parts: &[&[u8]]) -> Vec<u8> {
    let mut out = Vec::new();
    for part in parts {
        out.extend_from_slice(&(part.len() as u32).to_be_bytes());
        out.extend_from_slice(part);
    }
    out
}

/// Argon2id(salt, framed IKM) -> 32-byte master secret. `salt` is the
/// room's stored (cleartext) salt -- see room.rs's `RoomHeader`.
pub fn derive_master_secret(ikm_parts: &[&[u8]], salt: &[u8; 32]) -> [u8; MASTER_SECRET_LEN] {
    let framed = frame_ikm(ikm_parts);
    let params = Params::new(ARGON2_MEM_KIB, ARGON2_ITERATIONS, ARGON2_LANES, Some(MASTER_SECRET_LEN))
        .expect("static Argon2 params are valid");
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut out = [0u8; MASTER_SECRET_LEN];
    argon2
        .hash_password_into(&framed, salt, &mut out)
        .expect("static-length output always fits Argon2's output range");
    out
}

/// HKDF-Expand(master_secret, info) -> `len` bytes. Shared plumbing for
/// both `derive_slot_index` and `derive_header_key`.
fn expand(master_secret: &[u8; MASTER_SECRET_LEN], info: &[u8], len: usize) -> Vec<u8> {
    let hk = Hkdf::<Sha256>::from_prk(master_secret).expect("32-byte PRK is valid for HKDF-SHA256");
    let mut out = vec![0u8; len];
    hk.expand(info, &mut out).expect("requested length is far below HKDF-SHA256's max");
    out
}

/// `slot_index = HKDF-Expand(master_secret, "cas:header-slot") mod n`.
pub fn derive_slot_index(master_secret: &[u8; MASTER_SECRET_LEN], n: usize) -> usize {
    assert!(n > 0, "slot count must be nonzero");
    let bytes = expand(master_secret, INFO_SLOT, 8);
    let v = u64::from_be_bytes(bytes.try_into().expect("expand(len=8) always returns 8 bytes"));
    (v % n as u64) as usize
}

/// 32-byte ChaCha20-Poly1305 key for header-content encryption.
pub fn derive_header_key(master_secret: &[u8; MASTER_SECRET_LEN]) -> [u8; 32] {
    let bytes = expand(master_secret, INFO_KEY, 32);
    bytes.try_into().expect("expand(len=32) always returns 32 bytes")
}

#[cfg(test)]
mod tests {
    use super::*;

    const SALT_A: [u8; 32] = [7u8; 32];
    const SALT_B: [u8; 32] = [9u8; 32];

    #[test]
    fn master_secret_is_deterministic() {
        let a = derive_master_secret(&[b"passphrase"], &SALT_A);
        let b = derive_master_secret(&[b"passphrase"], &SALT_A);
        assert_eq!(a, b);
    }

    #[test]
    fn master_secret_differs_by_salt() {
        let a = derive_master_secret(&[b"passphrase"], &SALT_A);
        let b = derive_master_secret(&[b"passphrase"], &SALT_B);
        assert_ne!(a, b);
    }

    #[test]
    fn master_secret_differs_by_ikm() {
        let a = derive_master_secret(&[b"passphrase-one"], &SALT_A);
        let b = derive_master_secret(&[b"passphrase-two"], &SALT_A);
        assert_ne!(a, b);
    }

    #[test]
    fn framing_prevents_concat_collision() {
        // ["ab", "c"] and ["a", "bc"] must not collide despite identical
        // concatenated bytes -- this is exactly what the length prefix
        // in frame_ikm is for.
        let a = derive_master_secret(&[b"ab", b"c"], &SALT_A);
        let b = derive_master_secret(&[b"a", b"bc"], &SALT_A);
        assert_ne!(a, b);
    }

    #[test]
    fn slot_and_key_subkeys_are_independent() {
        let secret = derive_master_secret(&[b"passphrase"], &SALT_A);
        let slot = derive_slot_index(&secret, 1_000_000);
        let key = derive_header_key(&secret);
        // Not a formal proof of independence, just a sanity check that
        // the two purposes don't degenerate to the same bytes.
        assert_ne!(slot as u64, u64::from_be_bytes(key[..8].try_into().unwrap()));
    }

    #[test]
    fn slot_index_deterministic_and_in_range() {
        let secret = derive_master_secret(&[b"passphrase"], &SALT_A);
        let n = 85;
        let a = derive_slot_index(&secret, n);
        let b = derive_slot_index(&secret, n);
        assert_eq!(a, b);
        assert!(a < n);
    }

    #[test]
    fn header_key_deterministic() {
        let secret = derive_master_secret(&[b"passphrase"], &SALT_A);
        let a = derive_header_key(&secret);
        let b = derive_header_key(&secret);
        assert_eq!(a, b);
    }
}
