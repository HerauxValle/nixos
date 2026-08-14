// &desc: "Shared settings plumbing: a Feature declares its own CLI name and setter, so adding a setting is a new file plus one registry-array entry, never a new match arm."
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::vault::Vault;

pub struct Feature {
    pub name: &'static str,
    pub set: fn(&Ctx, &Vault, bool, Option<&str>) -> Result<()>,
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
