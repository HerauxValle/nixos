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
    let Some(sep) = args.iter().position(|a| a == "--") else {
        eprintln!("usage: sandbox_poc [--debug] <new-root-dir> -- <cmd> [args...]");
        std::process::exit(2);
    };
    let new_root = std::path::PathBuf::from(&args[1]);
    let argv = &args[sep + 1..];
    if argv.is_empty() {
        eprintln!("usage: sandbox_poc [--debug] <new-root-dir> -- <cmd> [args...]");
        std::process::exit(2);
    }

    let flags = sandbox::namespaces::Flags { mount: true, pid: true, uts: true, ipc: true, user: true, net: false };

    match sandbox::run(&new_root, std::path::Path::new(".sandbox_poc_oldroot"), &flags, argv, debug, None, None) {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("sandbox_poc failed: {e}");
            std::process::exit(1);
        }
    }
}
