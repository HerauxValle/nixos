// &desc: "Verification checkpoint shared by every settings toggle: re-derives the vault's real LUKS secret from a passphrase (+keyfile) and tests it, gated per-feature by Meta.verify_required (or its built-in default)."
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::luks;
use crate::meta::Meta;
use crate::prompt;
use crate::secret::{combined_secret, resolve_keyfile};
use crate::vault::Vault;

/// Features that require verification unless a vault explicitly opts out
/// via `cas <vault> settings verification <feature> disable`. These are
/// the settings that control whether a protection persists — exactly
/// what an attacker with root but not the passphrase would target —
/// plus `keyfileReset`, which is irreversible (old key material is gone
/// the moment the new slot verifies) and therefore deserves the same bar.
fn default_requires_verification(feature: &str) -> bool {
    matches!(feature, "ransomwareProtection" | "backupAuto" | "verification" | "keyfileReset")
}

pub fn requires_verification(meta: &Meta, feature: &str) -> bool {
    meta.verify_required
        .as_ref()
        .and_then(|overrides| overrides.get(feature).copied())
        .unwrap_or_else(|| default_requires_verification(feature))
}

/// No-op — never prompts — if `feature` doesn't currently require
/// verification. Otherwise resolves `pw` (prompting if not given),
/// re-derives the real vault secret, and dies if it doesn't unlock the
/// vault. For callers that don't need the passphrase for anything else
/// afterward (ransomwareProtection, backupAuto, embed, strip, ...) — use
/// `gate_pw` instead for any command that always needs a real passphrase
/// regardless of whether verification is on, to avoid prompting twice.
pub fn gate(ctx: &Ctx, vault: &Vault, feature: &str, pw: Option<&str>) -> Result<()> {
    gate_inner(ctx, vault, feature, pw).map(|_| ())
}

/// Same check as `gate`, but always returns a resolved passphrase ready
/// to use — prompting once whether or not verification applied, instead
/// of once here and again in the caller's own crypto operation. For
/// commands like `encryption`/`2fa`/`keyfile reset`/`keyfile activate`
/// that need a real passphrase unconditionally.
pub fn gate_pw(ctx: &Ctx, vault: &Vault, feature: &str, pw: Option<&str>) -> Result<String> {
    match gate_inner(ctx, vault, feature, pw)? {
        Some(resolved) => Ok(resolved),
        None => prompt::get_pw(ctx, pw),
    }
}

/// `Some(pw)` if verification ran (and passed) and resolved a
/// passphrase in the process; `None` if `feature` didn't require it, in
/// which case nothing was prompted or checked.
fn gate_inner(ctx: &Ctx, vault: &Vault, feature: &str, pw: Option<&str>) -> Result<Option<String>> {
    let mut meta = Meta::read(&vault.img);
    if !requires_verification(&meta, feature) {
        return Ok(None);
    }

    let pw = prompt::get_pw(ctx, pw)?;
    let secret = match meta.keyfile.clone() {
        Some(cached) => {
            let kf_path = resolve_keyfile(ctx, &cached, &mut meta, &vault.img)?;
            combined_secret(&pw, &crate::keyfile::read_bytes(&kf_path)?)
        }
        None => pw.as_bytes().to_vec(),
    };

    Meta::strip(&vault.img)?;
    let ok = luks::test(&vault.img, &secret);
    meta.write(&vault.img)?;
    if !ok {
        die!("wrong passphrase — could not verify vault");
    }
    Ok(Some(pw))
}
