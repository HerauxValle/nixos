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

pub fn run(ctx: &Ctx, base: &Path, name: &str, size: Option<u64>, pw: &str, strength: Strength, test: bool) -> Result<()> {
    let vault = Vault::resolve(base, name);
    // `Vault::lock_exclusive` (already held by the caller) now locks a
    // sibling `.lock` file rather than the image itself, so no
    // placeholder image gets created and a plain `exists()` is safe --
    // the lock still closes the "two concurrent creates" TOCTOU race,
    // it just no longer needs to be observable via the image file.
    if vault.img.exists() {
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

    logf!(ctx, "[cas] creating vault '{name}' ({size} MiB, strength={strength}) ...");

    // `size` is the usable payload -- `config::LUKS_DATA_OFFSET_MB` is on
    // top of this, so the file itself needs to be that much bigger for
    // the payload to actually come out to what was requested.
    let size_arg = format!("{}M", size + crate::config::LUKS_DATA_OFFSET_MB);
    let img_str = vault.img.to_string_lossy().into_owned();
    proc::run("truncate", &["-s", &size_arg, &img_str])?;

    let result: Result<()> = (|| {
        luks::format_vault_ex(&vault.img, pw.as_bytes(), strength)?;
        udisks::chown_to_real_user(&vault.img)?;
        udisks::loop_setup(&vault.img);
        if test {
            let mut meta = Meta::read(&vault.img);
            meta.ephemeral = Some(true);
            meta.write(&vault.img)?;
        }
        Ok(())
    })();

    if let Err(e) = result {
        let _ = std::fs::remove_file(&vault.img);
        return Err(e);
    }

    logf!(ctx, "[✓] vault created: {}", vault.img.display());
    if test {
        logf!(ctx, "  [i] --test vault: 'close' will delete this .img automatically");
    }
    logf!(ctx, "    open it with:  cas {name} open");
    Ok(())
}
