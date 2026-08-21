// &desc: "`rootfs default <name>|--clear|` -- sets/clears/shows the `.rootfs.d/default -> <name>` symlink `exec` falls back to when multiple environments exist and none was named explicitly via --rootfs."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::security::sandbox::rootfs::{default_target, ensure_dir, set_default, validate_name};
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::vault::Vault;

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        None => show(ctx, vault),
        Some("--clear") => {
            gate_inner(ctx, vault, "sandbox", pw)?;
            set_default(vault, None)?;
            logf!(ctx, "[✓] default cleared");
            Ok(())
        }
        Some(name) => {
            validate_name(name)?;
            let dir = ensure_dir(vault)?;
            if !dir.join(name).exists() {
                die!("rootfs environment '{name}' doesn't exist -- see 'cas <vault> settings security sandbox rootfs list'");
            }
            gate_inner(ctx, vault, "sandbox", pw)?;
            set_default(vault, Some(name))?;
            logf!(ctx, "[✓] default set to '{name}'");
            Ok(())
        }
    }
}

fn show(ctx: &Ctx, vault: &Vault) -> Result<()> {
    match default_target(vault) {
        Some(name) => logf!(ctx, "  default: {name}"),
        None => logf!(ctx, "  default: (none)"),
    }
    Ok(())
}
