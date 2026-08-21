// &desc: "`cas <vault> settings security zeroize enable|disable` — controls whether the derived LUKS secret is locked into RAM (mlock, can't be swapped to disk unencrypted while in use) and scrubbed from memory the moment it goes out of scope. Default on; disabling has no legitimate use case but the toggle exists to match every other security feature's shape."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry::Feature;
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

pub const FEATURE: Feature = Feature {
    name: "zeroize",
    set,
    get: is_enabled,
};

pub fn is_enabled(meta: &Meta) -> bool {
    meta.zeroize != Some(false)
}

pub fn set(ctx: &Ctx, vault: &Vault, enable: bool, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "zeroize", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.zeroize = (!enable).then_some(false);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;

    if enable {
        logf!(ctx, "[✓] zeroize enabled for '{}'", vault.name);
        logf!(ctx, "    the derived key is locked into RAM (can't be swapped to disk) while in use, and scrubbed from memory as soon as it goes out of scope");
    } else {
        logf!(ctx, "[✓] zeroize disabled for '{}'", vault.name);
        logf!(ctx, "    the derived key is left unlocked and in freed memory until something else reuses it");
    }
    Ok(())
}
