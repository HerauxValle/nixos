// &desc: "`cas all close` / `cas quit` — lazily unmount and close every casvault_* mapper on the machine, regardless of where its vault lives."
use crate::config::MAPPER_PREFIX;
use crate::ctx::Ctx;
use crate::error::Result;
use crate::logf;
use crate::proc;

pub fn run(ctx: &Ctx) -> Result<()> {
    logf!(ctx, "[cas] closing all open vaults ...");
    let mapper_marker = format!("{MAPPER_PREFIX}_");

    if let Ok(mounts) = std::fs::read_to_string("/proc/mounts") {
        for line in mounts.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[0].contains(&mapper_marker) {
                proc::run_silent("umount", &["-l", parts[1]]);
            }
        }
    }

    if let Ok(entries) = std::fs::read_dir("/dev/mapper") {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with(&mapper_marker) {
                proc::run_silent("cryptsetup", &["close", &name]);
            }
        }
    }

    logf!(ctx, "[✓] all vaults closed");
    Ok(())
}
