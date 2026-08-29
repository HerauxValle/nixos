// &desc: "`cas <vault> toggle` — open if closed, close if open; skips the shell-history warning/stdin dance `open` does since it's meant for a keybind."
use std::path::Path;

use crate::commands::{close, open};
use crate::ctx::Ctx;
use crate::error::Result;
use crate::meta::Meta;
use crate::prompt;
use crate::vault::Vault;

pub fn run(
    ctx: &Ctx,
    vault: &Vault,
    pw: Option<&str>,
    kf_override: Option<&Path>,
    explicit_kf: bool,
    kf_cache_hint: Option<&Path>,
) -> Result<()> {
    if vault.is_mount() {
        return close::run(ctx, vault, false);
    }
    let meta = Meta::read(&vault.img);
    if meta.is_encryption_bypassed() {
        return open::run(ctx, vault, "", kf_override, explicit_kf, kf_cache_hint);
    }
    let pw = match pw {
        Some(p) if !p.is_empty() => p.to_string(),
        _ => prompt::ask_secret(ctx, "passphrase")?,
    };
    open::run(ctx, vault, &pw, kf_override, explicit_kf, kf_cache_hint)
}
