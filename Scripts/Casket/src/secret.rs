// &desc: "Derives the LUKS secret from a passphrase (+ optional 2FA keyfile), and resolves a vault's keyfile path, prompting interactively if it moved."
use std::path::{Path, PathBuf};

use base64::Engine;
use sha2::{Digest, Sha256};
use zeroize::Zeroize;

use crate::commands::settings::security::zeroize::is_enabled as zeroize_enabled;
use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::logf;
use crate::meta::Meta;
use crate::prompt;

const B64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

const PASSPHRASE_ALPHABET: &[u8] =
    b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*-_=+?";

/// A strong random passphrase — shared by `create`'s "leave empty to
/// generate one" and `auth passwd`'s equivalent, so rotating *to* a
/// strong passphrase is exactly as easy as creating one was (previously
/// `auth passwd` just refused an empty new passphrase, an inconsistency
/// with `create`'s own behavior for no real reason).
pub fn generate_passphrase() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    (0..28)
        .map(|_| PASSPHRASE_ALPHABET[rng.gen_range(0..PASSPHRASE_ALPHABET.len())] as char)
        .collect()
}

/// Non-blocking — `create`/`auth passwd` warn on a `Some(..)` result but
/// never refuse it; the point is catching an obviously weak choice at
/// the one moment someone would actually read the warning, not
/// gatekeeping. zxcvbn scores 0 (trivial) through 4 (strong); anything
/// below 3 gets a warning, using its own pattern-match reasoning
/// (dictionary hit, keyboard pattern, date, repeat, ...) plus an
/// offline-attack crack-time estimate — the actual number that matters
/// against someone with the raw `.img` file and no rate limit to
/// respect, not an online-login-attempt estimate.
pub fn weakness_warning(pw: &str) -> Option<String> {
    let estimate = zxcvbn::zxcvbn(pw, &[]);
    if estimate.score() >= zxcvbn::Score::Three {
        return None;
    }
    let crack_time = estimate.crack_times().offline_slow_hashing_1e4_per_second();
    let reason = estimate
        .feedback()
        .and_then(|f| f.warning())
        .map(|w| w.to_string())
        .unwrap_or_else(|| "no specific reason given".to_string());
    Some(format!("{reason} (est. offline crack time: {crack_time})"))
}

/// The derived LUKS secret — wraps the raw bytes so they get scrubbed
/// from memory the moment this goes out of scope, unless `settings
/// security zeroize` is off for this vault. Derefs to `&[u8]` so every
/// existing call site (cryptsetup stdin, `luks::test`/`slot_cycle`)
/// keeps working unchanged.
pub struct Secret {
    bytes: Vec<u8>,
    should_zeroize: bool,
}

impl Secret {
    fn new(bytes: Vec<u8>, meta: &Meta) -> Self {
        let should_zeroize = zeroize_enabled(meta);
        // Locks the pages backing `bytes` into RAM for as long as this
        // Secret lives, so the key material can't get written to swap
        // (unencrypted, outside cas's control) while it's actively in
        // use — zeroize alone only covers *after* use. Same toggle
        // governs both: `settings security zeroize` is "harden how the
        // secret is held in memory" as a whole, not two separate knobs.
        // Best-effort: mlock can fail under RLIMIT_MEMLOCK on some
        // systems, silently skipped rather than treated as fatal — the
        // vault operation itself doesn't depend on this succeeding.
        if should_zeroize && !bytes.is_empty() {
            unsafe {
                libc::mlock(bytes.as_ptr() as *const libc::c_void, bytes.len());
            }
        }
        Secret { bytes, should_zeroize }
    }
}

impl Drop for Secret {
    fn drop(&mut self) {
        if self.should_zeroize {
            // Zero while still locked — the write itself is guaranteed
            // to land on the resident page, not race a swap-out that
            // could otherwise leave a stale plaintext copy on disk.
            self.bytes.zeroize();
            if !self.bytes.is_empty() {
                unsafe {
                    libc::munlock(self.bytes.as_ptr() as *const libc::c_void, self.bytes.len());
                }
            }
        }
    }
}

impl std::ops::Deref for Secret {
    type Target = [u8];
    fn deref(&self) -> &[u8] {
        &self.bytes
    }
}

/// hex(SHA-256(passphrase || keyfile bytes)) — matches the Python
/// original's `hashlib.sha256(pw.encode() + kf_bytes).hexdigest().encode()`
/// exactly, including returning the hex *string* (not the raw digest) as
/// the LUKS secret.
pub fn combined_secret(pw: &str, kf_bytes: &[u8]) -> Vec<u8> {
    let mut hasher = Sha256::new();
    hasher.update(pw.as_bytes());
    hasher.update(kf_bytes);
    let digest = hasher.finalize();

    let mut hex = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write;
        write!(hex, "{byte:02x}").unwrap();
    }
    hex.into_bytes()
}

pub fn b64_encode(bytes: &[u8]) -> String {
    B64.encode(bytes)
}

fn b64_decode(s: &str) -> Result<Vec<u8>> {
    B64.decode(s)
        .map_err(|e| CasError::new(format!("corrupt autokey in vault metadata: {e}")))
}

/// Decode the stored autokey (the full LUKS secret for an
/// encryption=off vault) straight from metadata. Callers that already
/// know `meta.is_encryption_bypassed()` use this directly instead of
/// going through `get_secret`, matching `cmd_open`'s own top-level
/// bypass check, which — unlike `get_secret`'s internal one — applies
/// unconditionally rather than only when no keyfile override is given.
pub fn decode_autokey(meta: &Meta) -> Result<Secret> {
    let bytes = b64_decode(meta.autokey.as_deref().ok_or_else(|| CasError::new("missing autokey"))?)?;
    Ok(Secret::new(bytes, meta))
}

/// Absolute, `.`/`..`-normalized form of `path`, without touching the
/// filesystem. Deliberately not `fs::canonicalize`: under sudo, a
/// removable-drive mountpoint may not exist yet at the moment this runs
/// (see keyfile_mount.rs), and canonicalize() hard-errors on that. This
/// mirrors Python's `Path.resolve(strict=False)` for the normalization
/// part; existence is always checked separately by the caller afterward.
pub fn resolve_lexically(path: &Path) -> PathBuf {
    let abs = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().unwrap_or_default().join(path)
    };
    let mut out = PathBuf::new();
    for comp in abs.components() {
        match comp {
            std::path::Component::ParentDir => {
                out.pop();
            }
            std::path::Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Return `(secret_bytes, meta)`, handling 2FA and the encryption=off
/// autokey bypass transparently. Pass `meta` in if the caller already has
/// a copy (e.g. taken before `Meta::strip`).
pub fn get_secret(
    ctx: &Ctx,
    img: &Path,
    pw: &str,
    kf_override: Option<&Path>,
    kf_cache_hint: Option<&Path>,
    meta: Option<Meta>,
) -> Result<(Secret, Meta)> {
    let mut meta = meta.unwrap_or_else(|| Meta::read(img));

    if meta.is_encryption_bypassed() && kf_override.is_none() {
        let raw = b64_decode(meta.autokey.as_deref().unwrap())?;
        let secret = Secret::new(raw, &meta);
        return Ok((secret, meta));
    }

    if !meta.has_2fa() {
        let secret = Secret::new(pw.as_bytes().to_vec(), &meta);
        return Ok((secret, meta));
    }

    let cached = meta.keyfile.clone().unwrap();
    let candidate: PathBuf = kf_override
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from(&cached));
    let mut kf_path = resolve_lexically(&candidate);

    if !kf_path.exists() {
        if ctx.quiet || kf_override.is_some() {
            die!("keyfile not found: {}", kf_path.display());
        }
        logf!(ctx, "  [!] keyfile not found at cached path: {}", kf_path.display());
        let input = prompt::ask(ctx, "  keyfile path", None)?;
        if input.is_empty() {
            die!("keyfile is required for this 2FA vault");
        }
        kf_path = resolve_lexically(Path::new(&input));
        if !kf_path.exists() {
            die!("keyfile not found: {}", kf_path.display());
        }
    }

    if !kf_path.is_file() {
        die!("keyfile is not a file: {}", kf_path.display());
    }

    // Cache the *logical* source path (e.g. the removable drive's
    // /run/media/.../*.key location), never `kf_path` itself when the
    // caller staged it first -- `kf_path` may be a throwaway temp copy
    // (see keyfile_mount.rs's `ensure_keyfile_mounted`, which reads a
    // removable drive's keyfile via raw block access and stages the
    // bytes into a mode-0600 temp file deleted on drop). Caching that
    // ephemeral path used to poison `meta.keyfile` with a path that was
    // already gone by the next session, permanently breaking the
    // removable-drive auto-recovery `ensure_keyfile_mounted` exists to
    // provide -- confirmed in the wild 2026-08-09.
    let to_cache = kf_cache_hint.unwrap_or(&kf_path);
    if to_cache.to_string_lossy() != cached {
        meta.keyfile = Some(to_cache.to_string_lossy().into_owned());
    }

    let kf_bytes = crate::keyfile::read_bytes(&kf_path)?;
    let secret = Secret::new(combined_secret(pw, &kf_bytes), &meta);
    Ok((secret, meta))
}

/// Resolve a keyfile path, prompting interactively if it's not found at
/// the cached location. Persists the updated path into `meta` (writing it
/// to `img` immediately) if the user gave a new one.
pub fn resolve_keyfile(ctx: &Ctx, cached: &str, meta: &mut Meta, img: &Path) -> Result<PathBuf> {
    let mut kf_path = resolve_lexically(Path::new(cached));
    if kf_path.exists() {
        return Ok(kf_path);
    }
    if ctx.quiet {
        die!("keyfile not found: {}", kf_path.display());
    }
    logf!(ctx, "  [!] keyfile not found at cached path: {}", kf_path.display());
    let input = prompt::ask(ctx, "  keyfile path", None)?;
    if input.is_empty() {
        die!("keyfile is required — cannot continue without it");
    }
    kf_path = resolve_lexically(Path::new(&input));
    if !kf_path.exists() {
        die!("keyfile not found: {}", kf_path.display());
    }
    meta.keyfile = Some(kf_path.to_string_lossy().into_owned());
    meta.write(img)?;
    logf!(ctx, "  [i] updated cached keyfile path");
    Ok(kf_path)
}
