// &desc: "`cas <vault> settings security sandbox cgroups set --mem <val> --cpu <percent> --pids <n> | clear | state` -- per-vault resource limits for `exec` sessions, stored in Meta (sandbox_cgroup_mem/cpu/pids), not tamper-HMAC-covered (resource management, not a protection toggle -- see meta/mod.rs's doc comment on those fields). Storage/validation only; sandbox::cgroup owns the actual cgroupfs mechanics, applied fresh each `exec` from whatever's stored here."
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::sandbox::cgroup::Spec;
use crate::vault::Vault;

pub fn active(meta: &Meta) -> Spec {
    Spec { mem: meta.sandbox_cgroup_mem.clone(), cpu: meta.sandbox_cgroup_cpu, pids: meta.sandbox_cgroup_pids }
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    match extra.first().map(String::as_str) {
        Some("set") => set(ctx, vault, &extra[1..], pw),
        Some("clear") => clear(ctx, vault, pw),
        Some("state") => state(ctx, vault),
        _ => die!("usage: cas <vault> settings security sandbox cgroups set [--mem <val>] [--cpu <percent>] [--pids <n>] | clear | state"),
    }
}

fn set(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let mut spec = active(&Meta::read(&vault.img));
    let mut i = 0;
    let mut touched = false;
    while i < extra.len() {
        match extra[i].as_str() {
            "--mem" => {
                let Some(v) = extra.get(i + 1) else { die!("--mem requires a value, e.g. '512M'") };
                if crate::sandbox::cgroup::parse_bytes(v).is_none() {
                    die!("invalid --mem value '{v}' -- expected e.g. '512M', '1G', or a plain byte count");
                }
                spec.mem = Some(v.clone());
                touched = true;
                i += 2;
            }
            "--cpu" => {
                let Some(v) = extra.get(i + 1) else { die!("--cpu requires a percent value, e.g. '50'") };
                let Ok(percent) = v.parse::<u32>() else { die!("invalid --cpu value '{v}' -- expected a plain percentage, e.g. '50'") };
                spec.cpu = Some(percent);
                touched = true;
                i += 2;
            }
            "--pids" => {
                let Some(v) = extra.get(i + 1) else { die!("--pids requires a value, e.g. '64'") };
                let Ok(pids) = v.parse::<u32>() else { die!("invalid --pids value '{v}' -- expected a plain integer") };
                spec.pids = Some(pids);
                touched = true;
                i += 2;
            }
            other => die!("unknown flag '{other}' -- expected --mem/--cpu/--pids"),
        }
    }
    if !touched {
        die!("usage: cas <vault> settings security sandbox cgroups set [--mem <val>] [--cpu <percent>] [--pids <n>]\n    at least one of --mem/--cpu/--pids is required");
    }

    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.sandbox_cgroup_mem = spec.mem;
    meta.sandbox_cgroup_cpu = spec.cpu;
    meta.sandbox_cgroup_pids = spec.pids;
    // Not HMAC-refreshed -- these fields are deliberately excluded from
    // tamper coverage (resource limits, not a protection toggle), same
    // as backup_auto/backup_auto_keep. `verified` above is still needed
    // to gate the *action* of changing this at all.
    let _ = verified;
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] cgroup limits updated for '{}'", vault.name);
    Ok(())
}

fn clear(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.sandbox_cgroup_mem = None;
    meta.sandbox_cgroup_cpu = None;
    meta.sandbox_cgroup_pids = None;
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] cgroup limits cleared for '{}'", vault.name);
    Ok(())
}

fn state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let spec = active(&meta);
    let width = registry::column_width(&["cgroups"]);
    let value = if spec.is_empty() {
        "unlimited".to_string()
    } else {
        let mut parts = Vec::new();
        if let Some(m) = &spec.mem {
            parts.push(format!("mem={m}"));
        }
        if let Some(c) = spec.cpu {
            parts.push(format!("cpu={c}%"));
        }
        if let Some(p) = spec.pids {
            parts.push(format!("pids={p}"));
        }
        parts.join(" ")
    };
    logf!(ctx, "  {}", registry::kv_line("cgroups", &value, width));
    Ok(())
}
