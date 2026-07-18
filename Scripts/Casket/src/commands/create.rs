// &desc: "`cas <vault> create` — allocate the .img file, format it with LUKS, and hand ownership back to the real user."
use std::path::Path;

use crate::config::Strength;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::luks;
use crate::proc;
use crate::prompt;
use crate::size::parse_size;
use crate::udisks;
use crate::vault::Vault;

const PASSPHRASE_ALPHABET: &[u8] =
    b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*-_=+?";

fn generate_passphrase() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    (0..28)
        .map(|_| PASSPHRASE_ALPHABET[rng.gen_range(0..PASSPHRASE_ALPHABET.len())] as char)
        .collect()
}

pub fn run(ctx: &Ctx, base: &Path, name: &str, size: Option<u64>, pw: &str, strength: Strength) -> Result<()> {
    let vault = Vault::resolve(base, name);
    if vault.img.exists() {
        die!("vault '{name}' already exists at {}", vault.img.display());
    }

    let size = match size {
        Some(s) => s,
        None => parse_size(&prompt::ask(ctx, "size (e.g. 1G, 500M, 2048)", Some("1G"))?)?,
    };

    let generated;
    let pw: &str = if pw.is_empty() {
        generated = generate_passphrase();
        logf!(ctx, "  [i] generated passphrase: {generated}");
        logf!(ctx, "      Save this — it cannot be recovered!");
        &generated
    } else {
        pw
    };

    logf!(ctx, "[cas] creating vault '{name}' ({size} MiB, strength={strength}) ...");

    let size_arg = format!("{size}M");
    let img_str = vault.img.to_string_lossy().into_owned();
    proc::run("truncate", &["-s", &size_arg, &img_str])?;

    let result: Result<()> = (|| {
        luks::format_vault(&vault.img, pw.as_bytes(), strength)?;
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
