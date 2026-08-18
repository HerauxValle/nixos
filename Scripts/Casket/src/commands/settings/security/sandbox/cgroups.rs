// &desc: "`cas <vault> settings security sandbox cgroups set --mem <val> --cpu <percent> --pids <n> | clear | state` -- per-vault resource limits for `exec` sessions, stored in Meta (sandbox_cgroup_mem/cpu/pids), not tamper-HMAC-covered (resource management, not a protection toggle -- see meta/mod.rs's doc comment on those fields). Storage/validation only; sandbox::cgroup owns the actual cgroupfs mechanics, applied fresh each `exec` from whatever's stored here."
use crate::cli_registry::Domain;
use crate::cli_registry::{self, Resolved};
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::Meta;
use crate::sandbox::cgroup::Spec;
use crate::vault::Vault;

/// This subtree's own flat, position-independent id space -- see
/// `network.rs`'s doc comment (the reference implementation this
/// pattern is copied from) for the full reasoning.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code1800,
    Code1801,
    Code1802,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[("1800", ActionId::Code1800), ("1801", ActionId::Code1801), ("1802", ActionId::Code1802)];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    /// Every code this domain knows how to handle -- consulted only by
    /// `cas debug parse-cli` (via `commands::debug::*_known_ids`) to
    /// compute the Ignored list, never by dispatch itself.
    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Finds the `cgroups` node inside the compiled-in registry tree
/// (`settings -> security -> sandbox -> cgroups`) once. If this ever
/// returns `None` it means `cli/registry.kdl` and this file's hardcoded
/// navigation path have drifted apart -- a build-time/test bug, not
/// something a user can trigger, hence the `expect`.
fn cgroups_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| {
            let path = ["settings", "security", "sandbox", "cgroups"];
            let mut nodes = cli_registry::get().vault.as_slice();
            for name in path {
                nodes = nodes.iter().find(|n| n.name == name).map(|n| n.children.as_slice()).unwrap_or(&[]);
            }
            nodes.to_vec()
        })
        .as_slice()
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation --
/// see `commands::debug`.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }

pub fn active(meta: &Meta) -> Spec {
    Spec { mem: meta.sandbox_cgroup_mem.clone(), cpu: meta.sandbox_cgroup_cpu, pids: meta.sandbox_cgroup_pids }
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(cgroups_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..], pw)
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> settings security sandbox cgroups set [--mem <val>] [--cpu <percent>] [--pids <n>] | clear | state")
        }
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, rest: &[String], pw: Option<&str>) -> Result<()> {
    match id {
        ActionId::Code1800 => set(ctx, vault, rest, pw),
        ActionId::Code1801 => clear(ctx, vault, pw),
        ActionId::Code1802 => state(ctx, vault),
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
                let Some(bytes) = crate::sandbox::cgroup::parse_bytes(v) else {
                    die!("invalid --mem value '{v}' -- expected e.g. '512M', '1G', or a plain byte count");
                };
                if bytes == 0 {
                    die!("--mem can't be 0 -- that would make every 'exec' session unusable (nothing can even start with no memory available)");
                }
                spec.mem = Some(v.clone());
                touched = true;
                i += 2;
            }
            "--cpu" => {
                let Some(v) = extra.get(i + 1) else { die!("--cpu requires a percent value, e.g. '50'") };
                let Ok(percent) = v.parse::<u32>() else { die!("invalid --cpu value '{v}' -- expected a plain percentage, e.g. '50'") };
                if percent == 0 {
                    die!("--cpu can't be 0 -- that would make every 'exec' session unusable (no CPU time available at all). Values over 100 are fine on a multi-core host (e.g. 400 = up to 4 cores).");
                }
                spec.cpu = Some(percent);
                touched = true;
                i += 2;
            }
            "--pids" => {
                let Some(v) = extra.get(i + 1) else { die!("--pids requires a value, e.g. '64'") };
                let Ok(pids) = v.parse::<u32>() else { die!("invalid --pids value '{v}' -- expected a plain integer") };
                if pids == 0 {
                    die!("--pids can't be 0 -- that would make every 'exec' session unusable (the kernel refuses to fork/exec anything at all under a 0 pid cap)");
                }
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
