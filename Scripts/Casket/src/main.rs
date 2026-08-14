// &desc: "Entry point: self-elevates via sudo if not already root, then hands off to cli::run() and prints/exit-codes whatever Result comes back."
mod btrfs;
mod cli;
mod color;
mod commands;
mod config;
mod ctx;
mod error;
mod help;
mod keyfile;
mod keyfile_mount;
mod luks;
mod meta;
mod migrations;
mod proc;
mod prompt;
mod secret;
mod size;
mod tamper;
mod udisks;
mod vault;
mod version;

use std::os::unix::process::CommandExt;

use error::CasError;

fn main() {
    elevate();

    match cli::run() {
        Ok(()) => {}
        Err(CasError::Msg(msg)) => {
            // die!() sites don't know about --no-log (that's parsed inside
            // cli::run(), whose Ctx has already gone out of scope by the
            // time its Result gets here), so check argv directly — same
            // effect as the original's `if not QUIET: log(...)` in die().
            if !std::env::args().any(|a| a == "--no-log") {
                println!("{}", color::auto(&format!("[x] {msg}")));
            }
            std::process::exit(1);
        }
        Err(CasError::Silent) => std::process::exit(1),
    }
}

/// Re-exec under sudo if not already root — mirrors the original's
/// `os.execvp("sudo", ["sudo"] + sys.argv)` self-elevation exactly,
/// including passing our own argv[0] through unchanged.
fn elevate() {
    if unsafe { libc::geteuid() } == 0 {
        return;
    }
    eprintln!("{}", color::auto("[i] elevating to sudo (if this fails, run with sudo manually)"));
    let err = std::process::Command::new("sudo").args(std::env::args()).exec();
    eprintln!("{}", color::auto(&format!("[x] failed to elevate: {err}")));
    std::process::exit(1);
}
