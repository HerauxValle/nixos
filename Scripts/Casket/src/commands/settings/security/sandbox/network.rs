// &desc: "`cas <vault> settings security sandbox network outbound|inbound ...` -- opt-in real connectivity for exec's 'net' namespace, separate from `namespaces enable net` itself (see sandbox::network's own doc comment for why the two are split: 'net' alone is always safe/contained loopback-only, these are the parts that actually mutate the host's routing/NAT). `outbound` and `inbound` are independent opt-ins, not one combined switch -- a sandbox might want to be reachable without ever phoning out, or vice versa, and folding them into a single toggle would hide that distinction for no real benefit."
use crate::cli_registry::Domain;
use crate::cli_registry::{self, Resolved};
use crate::commands::settings::gate::gate_inner;
use crate::commands::settings::registry;
use crate::commands::settings::security::sandbox::namespaces;
use crate::ctx::Ctx;
use crate::die;
use crate::error::Result;
use crate::logf;
use crate::meta::{Meta, PortMapping, Protocol};
use crate::tamper;
use crate::vault::Vault;

/// This subtree's own flat, position-independent id space -- see
/// `cli/registry.kdl`'s doc comment and `src/cli_registry/mod.rs`'s for
/// the full reasoning. Each variant is a bare number, not a semantic
/// name: the meaningful name lives on the handler function it maps to
/// below (`outbound_enable`, `inbound_add`, ...), never on the id
/// itself, so renaming/moving a node in the KDL file never requires
/// touching this. A dedicated enum per dispatch domain (not one global
/// enum shared across the whole CLI) is what keeps `dispatch_action`'s
/// `match` below exhaustive in a way the compiler actually enforces --
/// a shared enum would need a catch-all arm for every other domain's
/// ids too, and a catch-all silently swallows a forgotten new variant
/// instead of failing the build.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActionId {
    Code4001,
    Code4002,
    Code4003,
    Code4004,
    Code4005,
    Code4006,
    Code4007,
    Code4008,
    Code4009,
}

impl ActionId {
    const ALL: &'static [(&'static str, ActionId)] = &[
        ("4001", ActionId::Code4001),
        ("4002", ActionId::Code4002),
        ("4003", ActionId::Code4003),
        ("4004", ActionId::Code4004),
        ("4005", ActionId::Code4005),
        ("4006", ActionId::Code4006),
        ("4007", ActionId::Code4007),
        ("4008", ActionId::Code4008),
        ("4009", ActionId::Code4009),
    ];

    fn from_code(s: &str) -> Option<Self> {
        Self::ALL.iter().find(|(c, _)| *c == s).map(|(_, a)| *a)
    }

    /// Every code this domain knows how to handle -- consulted only by
    /// `cas debug parse-cli` (via `commands::debug::network_known_ids`)
    /// to compute the Ignored list, never by dispatch itself.
    pub fn known_codes() -> Vec<&'static str> {
        Self::ALL.iter().map(|(c, _)| *c).collect()
    }
}

/// Finds the `network` node inside the compiled-in registry tree
/// (`settings -> security -> sandbox -> network`) once. If this ever
/// returns `None` it means `cli/registry.kdl` and this file's hardcoded
/// navigation path have drifted apart -- a build-time/test bug, not
/// something a user can trigger, hence the `expect`.
fn network_children() -> &'static [cli_registry::TreeNode] {
    use std::sync::OnceLock;
    static CHILDREN: OnceLock<Vec<cli_registry::TreeNode>> = OnceLock::new();
    CHILDREN
        .get_or_init(|| {
            let path = ["settings", "security", "sandbox", "network"];
            let mut nodes = cli_registry::get().vault.as_slice();
            for name in path {
                nodes = nodes.iter().find(|n| n.name == name).map(|n| n.children.as_slice()).unwrap_or(&[]);
            }
            nodes.to_vec()
        })
        .as_slice()
}

pub fn dispatch(ctx: &Ctx, vault: &Vault, extra: &[String], pw: Option<&str>) -> Result<()> {
    let tokens: Vec<&str> = extra.iter().map(String::as_str).collect();
    match cli_registry::resolve(network_children(), &tokens) {
        Resolved::Leaf(node, consumed) => {
            let id = match node.id.as_deref().and_then(ActionId::from_code) {
                Some(id) => id,
                // Declared in the KDL but no matching Rust variant --
                // exactly the gap `debug parse-cli`'s Ignored list is
                // for. Refuse cleanly rather than silently no-op.
                None => die!("'{}' is declared but not wired up yet -- see 'cas debug parse-cli'", node.name),
            };
            dispatch_action(ctx, vault, id, &extra[consumed..], pw)
        }
        Resolved::Branch(_) | Resolved::NotFound => {
            die!("usage: cas <vault> settings security sandbox network outbound ... | inbound ...")
        }
    }
}

fn dispatch_action(ctx: &Ctx, vault: &Vault, id: ActionId, rest: &[String], pw: Option<&str>) -> Result<()> {
    match id {
        ActionId::Code4001 => outbound_enable(ctx, vault, pw),
        ActionId::Code4002 => outbound_disable(ctx, vault, pw),
        ActionId::Code4003 => outbound_state(ctx, vault),
        ActionId::Code4004 => inbound_add(ctx, vault, rest, pw),
        ActionId::Code4005 => inbound_remove(ctx, vault, rest.first(), pw),
        ActionId::Code4006 => inbound_list(ctx, vault),
        ActionId::Code4007 => inbound_enable(ctx, vault, pw),
        ActionId::Code4008 => inbound_disable(ctx, vault, pw),
        ActionId::Code4009 => inbound_state(ctx, vault),
    }
}

/// Exposed for `cas debug parse-cli`'s Ignored-list computation --
/// see `commands::debug`.
pub fn known_ids() -> Vec<&'static str> {
    ActionId::known_codes()
}

inventory::submit! { Domain { known_ids } }

pub fn outbound_is_enabled(meta: &Meta) -> bool {
    meta.sandbox_outbound == Some(true)
}

pub fn inbound_is_enabled(meta: &Meta) -> bool {
    meta.sandbox_inbound_enabled == Some(true)
}

pub fn inbound_ports(meta: &Meta) -> Vec<PortMapping> {
    meta.sandbox_inbound_ports.clone().unwrap_or_default()
}

fn require_net(vault: &Vault, meta: &Meta, feature: &str) -> Result<()> {
    if !namespaces::active(meta).iter().any(|n| n == "net") {
        die!(
            "'{feature}' requires the 'net' namespace to be active first -- run 'cas {} settings security sandbox namespaces enable net'",
            vault.name
        );
    }
    Ok(())
}

fn outbound_enable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let meta = Meta::read(&vault.img);
    require_net(vault, &meta, "outbound")?;
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = meta;
    meta.sandbox_outbound = Some(true);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] outbound access enabled for '{}' sandboxed exec sessions", vault.name);
    logf!(ctx, "  [!] this sets up a real veth pair + host NAT (MASQUERADE) rule for the");
    logf!(ctx, "      duration of each 'exec' session -- a step up from the isolated,");
    logf!(ctx, "      contained loopback-only default. Torn down automatically when 'exec'");
    logf!(ctx, "      exits (and swept on next use if a previous session crashed).");
    Ok(())
}

fn outbound_disable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.sandbox_outbound = None;
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] outbound access disabled for '{}' -- 'exec' sessions are back to loopback-only", vault.name);
    Ok(())
}

fn outbound_state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let width = registry::column_width(&["outbound"]);
    logf!(ctx, "  {}", registry::line("outbound", outbound_is_enabled(&meta), width));
    Ok(())
}

/// `inbound add <hostPort>[:<sandboxPort>] [--protocol tcp|udp]` --
/// `sandboxPort` defaults to `hostPort` when omitted. Adding a port
/// doesn't itself turn forwarding on -- see `inbound_enable`'s doc
/// comment for why that's a separate step.
fn inbound_add(ctx: &Ctx, vault: &Vault, args: &[String], pw: Option<&str>) -> Result<()> {
    let Some(spec) = args.first() else {
        die!("usage: cas <vault> settings security sandbox network inbound add <hostPort>[:<sandboxPort>] [--protocol tcp|udp]");
    };
    let protocol = match args.iter().position(|a| a == "--protocol") {
        Some(i) => match args.get(i + 1) {
            Some(p) => p.parse::<Protocol>().map_err(crate::error::CasError::Msg)?,
            None => die!("--protocol requires a value: tcp or udp"),
        },
        None => Protocol::Tcp,
    };
    let (host_port, sandbox_port) = match spec.split_once(':') {
        Some((h, s)) => (parse_port(h)?, parse_port(s)?),
        None => {
            let p = parse_port(spec)?;
            (p, p)
        }
    };

    let meta = Meta::read(&vault.img);
    require_net(vault, &meta, "inbound")?;
    let mut ports = inbound_ports(&meta);
    if ports.iter().any(|p| p.host_port == host_port && p.protocol == protocol) {
        die!("host port {host_port}/{protocol} is already forwarded for '{}' -- remove it first to change the target", vault.name);
    }
    // DNAT happens in PREROUTING, before the host's own routing/local-
    // delivery decision -- a real service already listening on this port
    // would have its traffic silently stolen the moment 'inbound enable'
    // takes effect, no bind conflict or error anywhere. Non-blocking
    // (someone may genuinely want to intentionally shadow a port they
    // plan to stop using), but worth flagging at the point of use rather
    // than letting it happen invisibly.
    if host_port_in_use(host_port, protocol == Protocol::Tcp) {
        logf!(ctx, "  [!] host port {host_port} already has something listening on it -- enabling forwarding will");
        logf!(ctx, "      redirect that traffic into the sandbox instead, not to whatever's using it now");
    }
    ports.push(PortMapping { host_port, sandbox_port, protocol });

    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = meta;
    meta.sandbox_inbound_ports = Some(ports);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] '{}' will forward host port {host_port}/{protocol} -> sandbox port {sandbox_port}", vault.name);
    if !inbound_is_enabled(&meta) {
        logf!(ctx, "  [i] inbound forwarding is still disabled -- 'settings security sandbox network inbound enable' to activate it");
    }
    Ok(())
}

fn inbound_remove(ctx: &Ctx, vault: &Vault, host_port: Option<&String>, pw: Option<&str>) -> Result<()> {
    let Some(host_port) = host_port else {
        die!("usage: cas <vault> settings security sandbox network inbound remove <hostPort>");
    };
    let host_port = parse_port(host_port)?;
    let meta = Meta::read(&vault.img);
    let mut ports = inbound_ports(&meta);
    let before = ports.len();
    ports.retain(|p| p.host_port != host_port);
    if ports.len() == before {
        die!("host port {host_port} isn't forwarded for '{}'", vault.name);
    }

    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = meta;
    meta.sandbox_inbound_ports = if ports.is_empty() { None } else { Some(ports) };
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] removed host port {host_port} from '{}'", vault.name);
    logf!(ctx, "  [i] takes effect on the next 'exec' session -- an already-running one keeps its forward until it exits");
    Ok(())
}

fn inbound_list(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let ports = inbound_ports(&meta);
    if ports.is_empty() {
        logf!(ctx, "  no inbound ports configured for '{}'", vault.name);
        return Ok(());
    }
    for p in &ports {
        logf!(ctx, "  {} -> {}  ({})", p.host_port, p.sandbox_port, p.protocol);
    }
    Ok(())
}

fn inbound_enable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let meta = Meta::read(&vault.img);
    require_net(vault, &meta, "inbound")?;
    if inbound_ports(&meta).is_empty() {
        die!("no inbound ports configured for '{}' -- 'inbound add <hostPort>' first", vault.name);
    }
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = meta;
    meta.sandbox_inbound_enabled = Some(true);
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] inbound forwarding enabled for '{}'", vault.name);
    logf!(ctx, "  [!] this opens the listed host port(s) to whatever's listening inside the");
    logf!(ctx, "      sandbox for the duration of each 'exec' session -- anything that can");
    logf!(ctx, "      reach this machine on those ports can reach the sandboxed process.");
    logf!(ctx, "      Torn down automatically when 'exec' exits (and swept on next use if a");
    logf!(ctx, "      previous session crashed).");
    Ok(())
}

fn inbound_disable(ctx: &Ctx, vault: &Vault, pw: Option<&str>) -> Result<()> {
    let verified = gate_inner(ctx, vault, "sandbox", pw)?;
    let mut meta = Meta::read(&vault.img);
    meta.sandbox_inbound_enabled = None;
    if let Some((_, secret)) = &verified {
        tamper::refresh(secret, &mut meta);
    }
    meta.write(&vault.img)?;
    logf!(ctx, "[✓] inbound forwarding disabled for '{}' (port list kept -- 'inbound list' to see it)", vault.name);
    Ok(())
}

fn inbound_state(ctx: &Ctx, vault: &Vault) -> Result<()> {
    let meta = Meta::read(&vault.img);
    let width = registry::column_width(&["inbound"]);
    logf!(ctx, "  {}", registry::line("inbound", inbound_is_enabled(&meta), width));
    Ok(())
}

/// Best-effort check of `/proc/net/{tcp,tcp6,udp,udp6}` for something
/// already bound to `port` -- these files list every socket's local
/// address as `<hex ip>:<hex port>`, with a `LISTEN` (`0A`) state column
/// for TCP specifically (UDP has no listen state; any bound entry
/// counts). Never fatal if unreadable -- this is a heads-up, not a
/// safety check the feature depends on.
fn host_port_in_use(port: u16, tcp: bool) -> bool {
    let port_hex = format!("{port:04X}");
    let files: &[&str] = if tcp { &["/proc/net/tcp", "/proc/net/tcp6"] } else { &["/proc/net/udp", "/proc/net/udp6"] };
    for path in files {
        let Ok(contents) = std::fs::read_to_string(path) else {
            continue;
        };
        for line in contents.lines().skip(1) {
            let fields: Vec<&str> = line.split_whitespace().collect();
            // fields[0] is the "sl" column (e.g. "1:"), local_address is fields[1].
            let Some(local) = fields.get(1) else { continue };
            let Some((_, local_port)) = local.split_once(':') else { continue };
            if !local_port.eq_ignore_ascii_case(&port_hex) {
                continue;
            }
            if !tcp {
                return true;
            }
            // TCP: only a real LISTEN socket counts -- st is field index 3.
            if fields.get(3).map(|s| s.eq_ignore_ascii_case("0A")).unwrap_or(false) {
                return true;
            }
        }
    }
    false
}

fn parse_port(s: &str) -> Result<u16> {
    match s.parse::<u16>() {
        Ok(0) | Err(_) => Err(crate::error::CasError::Msg(format!("invalid port '{s}' -- expected 1-65535"))),
        Ok(p) => Ok(p),
    }
}
