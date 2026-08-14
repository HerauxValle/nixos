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
/// directly (`settings <x> state`) or rolled up by `info`.
pub fn line(name: &str, enabled: bool) -> String {
    format!("  {name:<width$}  {}", if enabled { "enabled" } else { "disabled" }, width = 22)
}

/// A `[section]` header, grouping related state lines — used by `info`
/// and by any standalone `state` output that groups multiple features
/// (e.g. `settings verification state`) so names never need a manual
/// prefix like `verification-<feature>` to stay unambiguous.
pub fn section(title: &str) -> String {
    format!("\n[{title}]")
}

pub fn state(features: &[Feature], name: &str, ctx: &Ctx, vault: &Vault) -> Result<()> {
    match features.iter().find(|f| f.name == name) {
        Some(f) => {
            let meta = Meta::read(&vault.img);
            logf!(ctx, "{}", line(f.name, (f.get)(&meta)));
            Ok(())
        }
        None => die!(
            "unknown setting '{name}'\n    available: {}",
            features.iter().map(|f| f.name).collect::<Vec<_>>().join(", ")
        ),
    }
}
