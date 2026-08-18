// &desc: "Standalone throwaway harness for src/sandbox/ -- exercises the real unshare/pivot_root/proc/dev/reap sequence against a plain directory, with no vault involved. Not installed/shipped; dev-only proof that the primitives work before commands/exec/ wires them to a real vault mount. Usage: sandbox_poc <new-root-dir> -- <cmd> [args...]"
#[path = "../sandbox/mod.rs"]
mod sandbox;

fn main() {
    let mut args: Vec<String> = std::env::args().collect();
    let debug = if let Some(pos) = args.iter().position(|a| a == "--debug") {
        args.remove(pos);
        true
    } else {
        false
    };
    let net = if let Some(pos) = args.iter().position(|a| a == "--net") {
        args.remove(pos);
        true
    } else {
        false
    };
    let outbound = if let Some(pos) = args.iter().position(|a| a == "--outbound") {
        args.remove(pos);
        true
    } else {
        false
    };
    // --inbound <hostPort>[:<sandboxPort>][/udp] -- can be given more than once.
    let mut inbound = Vec::new();
    while let Some(pos) = args.iter().position(|a| a == "--inbound") {
        args.remove(pos);
        if pos >= args.len() {
            eprintln!("--inbound requires a value: <hostPort>[:<sandboxPort>][/udp]");
            std::process::exit(2);
        }
        let spec = args.remove(pos);
        let (spec, tcp) = match spec.strip_suffix("/udp") {
            Some(s) => (s, false),
            None => (spec.strip_suffix("/tcp").unwrap_or(&spec), true),
        };
        let (host_port, sandbox_port) = match spec.split_once(':') {
            Some((h, s)) => (h.parse().expect("bad host port"), s.parse().expect("bad sandbox port")),
            None => {
                let p = spec.parse().expect("bad port");
                (p, p)
            }
        };
        inbound.push(sandbox::network::PortForward { host_port, sandbox_port, tcp });
    }
    let Some(sep) = args.iter().position(|a| a == "--") else {
        eprintln!("usage: sandbox_poc [--debug] [--net] [--outbound] [--inbound <hostPort>[:<sandboxPort>][/udp]]... <new-root-dir> -- <cmd> [args...]");
        std::process::exit(2);
    };
    let new_root = std::path::PathBuf::from(&args[1]);
    let argv = &args[sep + 1..];
    if argv.is_empty() {
        eprintln!("usage: sandbox_poc [--debug] [--net] [--outbound] [--inbound <hostPort>[:<sandboxPort>][/udp]]... <new-root-dir> -- <cmd> [args...]");
        std::process::exit(2);
    }

    let flags = sandbox::namespaces::Flags { mount: true, pid: true, uts: true, ipc: true, user: true, net };
    let net_cfg = sandbox::network::Config { outbound, inbound };

    match sandbox::run(&new_root, std::path::Path::new(".sandbox_poc_oldroot"), &flags, argv, debug, None, None, None, net_cfg) {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("sandbox_poc failed: {e}");
            std::process::exit(1);
        }
    }
}
