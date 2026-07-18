// &desc: "Derives the LUKS secret from a passphrase (+ optional 2FA keyfile), and resolves a vault's keyfile path, prompting interactively if it moved."
use std::path::{Path, PathBuf};

use base64::Engine;
use sha2::{Digest, Sha256};

use crate::ctx::Ctx;
use crate::die;
use crate::error::{CasError, Result};
use crate::logf;
use crate::meta::Meta;
use crate::prompt;

const B64: base64::engine::GeneralPurpose = base64::engine::general_purpose::STANDARD;

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
pub fn decode_autokey(meta: &Meta) -> Result<Vec<u8>> {
    b64_decode(meta.autokey.as_deref().ok_or_else(|| CasError::new("missing autokey"))?)
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
    meta: Option<Meta>,
) -> Result<(Vec<u8>, Meta)> {
    let mut meta = meta.unwrap_or_else(|| Meta::read(img));

    if meta.is_encryption_bypassed() && kf_override.is_none() {
        let raw = b64_decode(meta.autokey.as_deref().unwrap())?;
        return Ok((raw, meta));
    }

    if !meta.has_2fa() {
        return Ok((pw.as_bytes().to_vec(), meta));
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

    if kf_path.to_string_lossy() != cached {
        meta.keyfile = Some(kf_path.to_string_lossy().into_owned());
    }

    let kf_bytes = std::fs::read(&kf_path)?;
    Ok((combined_secret(pw, &kf_bytes), meta))
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
