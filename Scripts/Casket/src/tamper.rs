// &desc: "Tamper-evidence for the fields that actually gate a protection (ransomwareProtection, verify_required, zeroize, bruteforceLockout, fileIntegrity, sandbox_enabled/namespaces/seccomp) -- an HMAC-SHA256 over just those fields, keyed by the vault's own derived LUKS secret. Verifiable only when the secret is known (open, or any --pass-bearing command), by design: a check that worked without the secret would also let an attacker forge a matching tag without it."
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
    bruteforce_lockout: &'a Option<bool>,
    // Not just the on/off bool -- the threshold itself gates *how much*
    // protection `bruteforceLockout` actually gives. An attacker who
    // could silently raise it (3 -> 999999, say) without ever touching
    // `bruteforce_lockout` would gut the feature's real strength while
    // `tampered`/`open` kept reporting "healthy", since nothing here
    // was checking this field at all until now.
    bruteforce_threshold: &'a Option<u32>,
    file_integrity: &'a Option<bool>,
    sandbox_enabled: &'a Option<bool>,
    sandbox_namespaces: &'a Option<Vec<String>>,
    sandbox_seccomp: &'a Option<std::collections::BTreeMap<String, String>>,
    sandbox_seccomp_profile_hash: &'a Option<std::collections::BTreeMap<String, String>>,
    // header_room deliberately NOT covered here -- it only describes
    // whether the room slack space has ever been provisioned (a
    // one-way ratchet with no security meaning of its own once true),
    // not a protection strength. header_offset/header_encryption are
    // the two that actually gate anything.
    header_offset: &'a Option<bool>,
    header_encryption: &'a Option<bool>,
}

/// Canonical bytes for just the protected fields — deterministic key
/// order (serde_json's default `Map` is BTreeMap-backed without the
/// `preserve_order` feature, which this crate doesn't enable).
fn protected_json(meta: &Meta) -> Vec<u8> {
    let p = Protected {
        ransomware_protection: &meta.ransomware_protection,
        verify_required: &meta.verify_required,
        zeroize: &meta.zeroize,
        bruteforce_lockout: &meta.bruteforce_lockout,
        bruteforce_threshold: &meta.bruteforce_threshold,
        file_integrity: &meta.file_integrity,
        sandbox_enabled: &meta.sandbox_enabled,
        sandbox_namespaces: &meta.sandbox_namespaces,
        sandbox_seccomp: &meta.sandbox_seccomp,
        sandbox_seccomp_profile_hash: &meta.sandbox_seccomp_profile_hash,
        header_offset: &meta.header_offset,
        header_encryption: &meta.header_encryption,
    };
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

/// Overwrite the protected fields with the maximally-protective value
/// for each — used when `verify()` returns `Tampered` and there's no
/// way to know what the legitimate prior values were. Always fails
/// toward *more* protection than less: worst case is an unwanted
/// protection turned on (mildly annoying, user turns it back off once
/// they've investigated), never a silently-weakened one.
///
/// Two fields don't follow the simple "flip to true = safer" rule:
///
/// `bruteforceLockout` — forcing this *on* isn't the safe direction,
/// it's the dangerous one. Unlike every other field here, this one has
/// a destructive, irreversible side effect (deletes the vault after N
/// wrong passphrase attempts) that the owner never actually opted into
/// if the trailer was tampered (or just corrupted by a bug) rather than
/// legitimately toggled. Silently turning that on as a "safety" measure
/// would trade a detection problem for a data-loss one. So this is the
/// one field forced *off* instead — losing a brute-force defense is
/// recoverable by re-enabling it; an unwanted vault deletion is not.
///
/// `fileIntegrity` — this field doesn't control anything itself, it
/// only *describes* what the on-disk container already is (set once,
/// at migration time; the container's real structure can't be changed
/// by editing this flag). Blindly setting it `true` on a container
/// that's actually plain LUKS would make `info` lie in the *other*
/// direction — claiming a protection that isn't really there. So this
/// checks reality instead, via `cryptsetup luksDump`, and stores
/// whatever's actually true.
/// `secret` is the vault's already-verified LUKS secret (available at
/// every call site — `open.rs`'s `check_tamper` runs right after the
/// real secret was resolved) — needed here because `header_offset`/
/// `header_encryption`'s ground truth can only be established by
/// actually trying to locate/open the header both ways (native front,
/// front-framed-encrypted, room slot plaintext, room slot encrypted),
/// not by inspecting bytes alone. See `header::relocate::ground_truth`.
pub fn reset_to_safe(img: &std::path::Path, secret: &[u8], meta: &mut Meta) {
    meta.ransomware_protection = Some(true);
    meta.zeroize = Some(true);
    meta.bruteforce_lockout = Some(false);
    // `bruteforce_threshold` is left untouched -- now HMAC-covered (so
    // a tampered value is correctly *detected*), but with the feature
    // itself forced off above, a stale/tampered threshold number is
    // inert either way; nothing reads it while lockout is disabled.
    meta.file_integrity = Some(crate::luks::has_integrity(img));
    // sandbox: forcing *on* has no destructive side effect (unlike
    // bruteforceLockout), so it follows the majority "more protective"
    // rule. Namespaces reset to the full set (every namespace isolated,
    // including `net` — the opposite of the offline-by-default install
    // default, but the *safe* direction under tampering is maximum
    // isolation, not the friendliest default). Existing seccomp entries
    // reset to "strict", never "none" — same reasoning as bruteforce's
    // exception, just in the opposite direction: there's no destructive
    // side effect to strict, so majority rule applies here too. Custom
    // hashes aren't reset — they're an integrity marker, not a
    // protection strength value.
    meta.sandbox_enabled = Some(true);
    meta.sandbox_namespaces = Some(vec!["mount".into(), "pid".into(), "uts".into(), "ipc".into(), "user".into(), "net".into()]);
    if let Some(seccomp) = meta.sandbox_seccomp.as_mut() {
        for preset in seccomp.values_mut() {
            *preset = "strict".to_string();
        }
    }
    let mut all_required = std::collections::BTreeMap::new();
    for f in crate::commands::settings::gate::GATED_FEATURES {
        all_required.insert(f.to_string(), true);
    }
    meta.verify_required = Some(all_required);

    // header_offset/header_encryption: neither "force both false" nor
    // "leave untouched" is safe (see header/relocate.rs's module doc)
    // -- re-derive from physical ground truth instead.
    let (offset, encryption) = crate::header::relocate::ground_truth(img, secret);
    meta.header_offset = Some(offset);
    meta.header_encryption = Some(encryption);
}
