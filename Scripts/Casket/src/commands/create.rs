// &desc: "`cas <vault> create` — allocate the .img file, format it with LUKS, and hand ownership back to the real user."
use std::path::Path;

use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::meta::Meta;
use crate::proc;
use crate::prompt;
use crate::secret::{generate_passphrase, weakness_warning};
use crate::size::parse_size;
use crate::udisks;
use crate::vault::Vault;

/// Below this, a fresh empty vault's initial dm-integrity wipe (the
/// whole device gets zeroed before first use) is fast enough that
/// defaulting the create-time prompt to "yes" doesn't surprise anyone
/// with a multi-minute wait; at or above it, the default flips to "no".
pub const INTEGRITY_PROMPT_THRESHOLD_MB: u64 = 20 * 1024;

pub fn run(ctx: &Ctx, base: &Path, name: &str, size: Option<u64>, pw: &str, strength: Strength, integrity: Option<bool>, interactive: bool) -> Result<()> {
    let vault = Vault::resolve(base, name);
    // Size, not `exists()` -- `Vault::lock_exclusive` (already held by
    // the caller at this point) creates a 0-byte placeholder to lock a
    // not-yet-created vault's name against a racing concurrent `create`,
    // so `exists()` alone can no longer tell "nothing here" from "a real
    // vault." A real image is always non-empty (`truncate`d to its size
    // before this check could ever see it in a race).
    if vault.img.metadata().map(|m| m.len() > 0).unwrap_or(false) {
        die!("vault '{name}' already exists at {}", vault.img.display());
    }

    let size = match size {
        Some(s) => s,
        None => parse_size(&prompt::ask(ctx, "size (e.g. 1G, 500M, 2048)", Some("1G"))?)?,
    };
    // Same floor `resize` already enforces -- without it, `create`
    // happily produces a vault too small for `mkfs.btrfs` to ever
    // format, discovered only at first `open` via a raw cryptsetup/
    // mkfs error instead of a clean error here.
    if size < crate::config::MIN_VAULT_MB {
        die!("minimum vault size is {} MiB", crate::config::MIN_VAULT_MB);
    }

    let integrity = match integrity {
        Some(v) => v,
        None if interactive => {
            let default_yes = size < INTEGRITY_PROMPT_THRESHOLD_MB;
            let ans = prompt::ask(
                ctx,
                "Enable file integrity protection? (detects corrupted/tampered files, adds ~15-20% storage overhead)",
                Some(if default_yes { "y" } else { "n" }),
            )?;
            matches!(ans.trim().to_lowercase().as_str(), "y" | "yes")
        }
        None => false,
    };

    let generated;
    let pw: &str = if pw.is_empty() {
        generated = generate_passphrase();
        logf!(ctx, "  [i] generated passphrase: {generated}");
        logf!(ctx, "      Save this — it cannot be recovered!");
        &generated
    } else {
        if let Some(warning) = weakness_warning(pw) {
            logf!(ctx, "  [!] weak passphrase: {warning}");
        }
        pw
    };

    let integrity_note = if integrity { ", fileIntegrity" } else { "" };
    logf!(ctx, "[cas] creating vault '{name}' ({size} MiB, strength={strength}{integrity_note}) ...");

    // `size` is meant as usable payload, not raw file size -- cryptsetup's
    // own historical 16 MiB default offset was already silently eaten out
    // of it before `LUKS_DATA_OFFSET_MB` existed, so grow the truncate
    // size by the delta beyond that old default rather than the new
    // constant outright, keeping "cas create --size 1G" giving the same
    // usable space it always did instead of shrinking by ~112 MiB.
    const HISTORICAL_DEFAULT_OFFSET_MB: u64 = 16;
    let truncate_mb = size + crate::config::LUKS_DATA_OFFSET_MB.saturating_sub(HISTORICAL_DEFAULT_OFFSET_MB);
    let size_arg = format!("{truncate_mb}M");
    let img_str = vault.img.to_string_lossy().into_owned();
    proc::run("truncate", &["-s", &size_arg, &img_str])?;

    let result: Result<()> = (|| {
        luks::format_vault_ex(&vault.img, pw.as_bytes(), strength, integrity)?;
        if integrity {
            Meta { file_integrity: Some(true), ..Meta::default() }.write(&vault.img)?;
        }
        udisks::chown_to_real_user(&vault.img)?;
        udisks::loop_setup(&vault.img);
        Ok(())
    })();

    if let Err(e) = result {
        let _ = std::fs::remove_file(&vault.img);
        return Err(e);
    }

    logf!(ctx, "[✓] vault created: {}", vault.img.display());
    logf!(ctx, "    open it with:  cas {name} open");
    Ok(())
}
