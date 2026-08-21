// &desc: "`cas <vault> settings verification <feature> enable|disable` — decides whether toggling <feature> requires re-proving the passphrase; toggling this is gated by its own current state, including on itself."
use std::collections::BTreeMap;

use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::tamper;
use crate::vault::Vault;

use super::gate;
use super::registry;

/// `cas <vault> settings verification state` (all gated features) or
/// `cas <vault> settings verification <feature> state` (just one).
pub fn state(ctx: &Ctx, vault: &Vault, feature: Option<&str>) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let targets: Vec<&str> = match feature {
        Some(f) => vec![f],
        None => gate::GATED_FEATURES.to_vec(),
    };
    logf!(ctx, "{}", registry::section("verification"));
    logf!(ctx, "{}", registry::VERIFICATION_NOTE);
    let width = registry::column_width(&targets);
    for f in &targets {
        logf!(ctx, "{}", registry::line(f, gate::requires_verification(&meta, f), width));
    }
    Ok(())
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, feature: &str, enable: bool, pw: Option<&str>) -> Result<()> {
    // Whether changing *any* feature's verification requirement needs
    // the passphrase first is controlled by the master "verification"
    // entry itself, not by the entry of whichever feature is being
    // targeted. If it does, gate_inner's resolved secret also refreshes
    // `verify_required`'s tamper-evidence HMAC (tamper.rs); if
    // verification is off, nothing is prompted/checked, same as before
    // tamper-evidence existed.
    let verified = gate::gate_inner(ctx, vault, "verification", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.verify_required
        .get_or_insert_with(BTreeMap::new)
        .insert(feature.to_string(), enable);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;

    logf!(
        ctx,
        "[✓] verification for '{feature}' {} on '{}'",
        if enable { "enabled" } else { "disabled" },
        vault.name
    );
    Ok(())
}
