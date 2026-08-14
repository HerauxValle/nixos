// &desc: "Tamper-evidence for the 3 fields that actually gate a protection (ransomwareProtection, verify_required, zeroize) -- an HMAC-SHA256 over just those fields, keyed by the vault's own derived LUKS secret. Verifiable only when the secret is known (open, or any --pass-bearing command), by design: a check that worked without the secret would also let an attacker forge a matching tag without it."
use hmac::{Hmac, Mac};
use serde::Serialize;
use sha2::Sha256;

use crate::meta::Meta;

type HmacSha256 = Hmac<Sha256>;

#[derive(Serialize)]
struct Protected<'a> {
    ransomware_protection: &'a Option<bool>,
    verify_required: &'a Option<std::collections::BTreeMap<String, bool>>,
    zeroize: &'a Option<bool>,
}

/// Canonical bytes for just the 3 protection fields — deterministic key
/// order (serde_json's default `Map` is BTreeMap-backed without the
/// `preserve_order` feature, which this crate doesn't enable).
fn protected_json(meta: &Meta) -> Vec<u8> {
    let p = Protected { ransomware_protection: &meta.ransomware_protection, verify_required: &meta.verify_required, zeroize: &meta.zeroize };
    serde_json::to_vec(&p).unwrap_or_default()
}

pub fn compute(secret: &[u8], meta: &Meta) -> String {
    let mut mac = HmacSha256::new_from_slice(secret).expect("HMAC accepts any key length");
    mac.update(&protected_json(meta));
    let tag = mac.finalize().into_bytes();
    tag.iter().map(|b| format!("{b:02x}")).collect()
}

/// Set `meta.meta_hmac` to the current fresh tag — call this every time
/// a verified write touches `ransomware_protection`/`verify_required`/
/// `zeroize`, right before `meta.write()`.
pub fn refresh(secret: &[u8], meta: &mut Meta) {
    meta.meta_hmac = Some(compute(secret, meta));
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    /// Tag matches — nothing's been edited outside a verified write.
    Healthy,
    /// A tag is stored but doesn't match the current fields.
    Tampered,
    /// No tag stored yet — a fresh vault, or one from before this
    /// feature existed. Not evidence of tampering, just no baseline.
    Unprotected,
}

pub fn verify(secret: &[u8], meta: &Meta) -> Status {
    let Some(stored) = &meta.meta_hmac else {
        return Status::Unprotected;
    };
    let expected = compute(secret, meta);
    // Constant-time compare -- a tamper-check that leaked timing info
    // about how many leading hex chars matched would be a small but
    // real oracle for guessing the stored tag.
    if stored.len() == expected.len() && stored.bytes().zip(expected.bytes()).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0 {
        Status::Healthy
    } else {
        Status::Tampered
    }
}

/// Overwrite the 3 protected fields with the maximally-protective value
/// for each — used when `verify()` returns `Tampered` and there's no
/// way to know what the legitimate prior values were. Always fails
/// toward *more* protection than less: worst case is an unwanted
/// protection turned on (mildly annoying, user turns it back off once
/// they've investigated), never a silently-weakened one.
pub fn reset_to_safe(meta: &mut Meta) {
    meta.ransomware_protection = Some(true);
    meta.zeroize = Some(true);
    let mut all_required = std::collections::BTreeMap::new();
    for f in crate::commands::settings::gate::GATED_FEATURES {
        all_required.insert(f.to_string(), true);
    }
    meta.verify_required = Some(all_required);
}
