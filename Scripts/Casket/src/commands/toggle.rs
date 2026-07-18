// &desc: "`cas <vault> toggle` — open if closed, close if open; skips the shell-history warning/stdin dance `open` does since it's meant for a keybind."
use std::path::Path;

use crate::commands::{close, open};
use crate::ctx::Ctx;
use crate::error::Result;
use crate::meta::Meta;
use crate::prompt;
use crate::vault::Vault;

pub fn run(ctx: &Ctx, vault: &Vault, pw: Option<&str>, kf_override: Option<&Path>) -> Result<()> {
    if vault.is_mount() {
        return close::run(ctx, vault);
    }
    let meta = Meta::read(&vault.img);
    if meta.is_encryption_bypassed() {
        return open::run(ctx, vault, "", kf_override);
    }
    let pw = match pw {
        Some(p) if !p.is_empty() => p.to_string(),
        _ => prompt::ask_secret(ctx, "passphrase")?,
    };
    open::run(ctx, vault, &pw, kf_override)
}
