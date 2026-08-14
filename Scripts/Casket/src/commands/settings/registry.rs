// &desc: "Shared settings plumbing: a Feature declares its own CLI name and setter, so adding a setting is a new file plus one registry-array entry, never a new match arm."
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::vault::Vault;

pub struct Feature {
    pub name: &'static str,
    pub set: fn(&Ctx, &Vault, bool, Option<&str>) -> Result<()>,
    pub get: fn(&Meta) -> bool,
}

pub fn dispatch(features: &[Feature], name: &str, enable: bool, ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    match features.iter().find(|f| f.name == name) {
        Some(f) => (f.set)(ctx, vault, enable, pw),
        None => die!(
            "unknown setting '{name}'\n    available: {}",
            features.iter().map(|f| f.name).collect::<Vec<_>>().join(", ")
        ),
    }
}

/// Shared `state` formatter — `<name>   enabled|disabled`, the same line
/// every enable|disable-shaped setting prints, whether asked for
/// directly (`settings <x> state`) or rolled up by `info`. `width`
/// should be the same value for every line printed together (see
/// `column_width`) so the value column lines up regardless of how long
/// any one name is.
pub fn line(name: &str, enabled: bool, width: usize) -> String {
    format!("  {name:<width$}{}", if enabled { "enabled" } else { "disabled" })
}

/// The column width to hand every `line()` call that's printed as part
/// of the same block — the longest name among them plus 8 spaces, so
/// the shortest name still gets visible breathing room and the longest
/// one lines up flush with an 8-space gap.
pub fn column_width(names: &[&str]) -> usize {
    names.iter().map(|n| n.len()).max().unwrap_or(0) + 8
}

/// Same column alignment as `line()`, for a plain `name  value` pair
/// that isn't an enabled/disabled state (e.g. `[general]`/`[auth]`
/// fields in `info`).
pub fn kv_line(name: &str, value: &str, width: usize) -> String {
    format!("  {name:<width$}{value}")
}

/// A `[section]` header, grouping related state lines — used by `info`
/// and by any standalone `state` output that groups multiple features
/// (e.g. `settings verification state`) so names never need a manual
/// prefix like `verification-<feature>` to stay unambiguous.
pub fn section(title: &str) -> String {
    format!("\n[{title}]")
}

/// Explains what enabled/disabled means specifically under
/// `[verification]`, where every line reuses a name that also appears
/// under `[settings]`/`[security]` with a different meaning (is the
/// setting itself on, vs. does toggling it require the passphrase).
pub const VERIFICATION_NOTE: &str = "  (requires passphrase before the setting below can be toggled)";

pub fn state(features: &[Feature], name: &str, ctx: &Ctx, vault: &Vault) -> Result<()> {
    match features.iter().find(|f| f.name == name) {
        Some(f) => {
            let meta = Meta::read(&vault.img);
            logf!(ctx, "{}", line(f.name, (f.get)(&meta), column_width(&[f.name])));
            Ok(())
        }
        None => die!(
            "unknown setting '{name}'\n    available: {}",
            features.iter().map(|f| f.name).collect::<Vec<_>>().join(", ")
        ),
    }
}
