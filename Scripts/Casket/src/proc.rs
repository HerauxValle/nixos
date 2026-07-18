// &desc: "Thin wrappers around std::process::Command — run-and-check, run-with-stdin, run-and-ignore, and run-and-capture — reused by every module that shells out."
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Output, Stdio};

use crate::error::{CasError, Result};

fn fail(program: &str, args: &[&str], stderr: &[u8]) -> CasError {
    CasError::new(format!(
        "{program} {} failed: {}",
        args.join(" "),
        String::from_utf8_lossy(stderr).trim()
    ))
}

/// Run a command, returning Err with the captured stderr on a nonzero
/// exit. Replaces the original's bare `subprocess.run(check=True)`, which
/// on failure let a raw Python traceback reach the user instead of a
/// clean `[x] ...` line.
pub fn run(program: &str, args: &[&str]) -> Result<()> {
    let out = Command::new(program)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output()
        .map_err(|e| CasError::new(format!("failed to run {program}: {e}")))?;
    if out.status.success() {
        Ok(())
    } else {
        Err(fail(program, args, &out.stderr))
    }
}

/// Run a command with `input` piped to its stdin, returning Err on a
/// nonzero exit. Used for every cryptsetup call that needs a secret:
/// `--key-file -` reads the key from stdin, so the secret never touches
/// disk (not even a briefly-lived temp file).
pub fn run_with_stdin(program: &str, args: &[&str], input: &[u8]) -> Result<()> {
    let out = spawn_with_stdin(program, args, input)?;
    if out.status.success() {
        Ok(())
    } else {
        Err(fail(program, args, &out.stderr))
    }
}

/// Same as `run_with_stdin` but reports success/failure as a bool instead
/// of an error — for probes where a nonzero exit is an expected, normal
/// outcome (testing a passphrase against one of several key slots).
pub fn run_with_stdin_status(program: &str, args: &[&str], input: &[u8]) -> bool {
    spawn_with_stdin(program, args, input)
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn spawn_with_stdin(program: &str, args: &[&str], input: &[u8]) -> Result<Output> {
    use std::io::Write;
    let mut child = Command::new(program)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| CasError::new(format!("failed to run {program}: {e}")))?;
    child
        .stdin
        .take()
        .expect("stdin was requested as piped")
        .write_all(input)?;
    Ok(child.wait_with_output()?)
}

/// Run a command, discarding both its exit status and its output — for
/// best-effort cleanup calls (umount, cryptsetup close) that may fail
/// legitimately when there's nothing to clean up.
pub fn run_silent(program: &str, args: &[&str]) {
    let _ = Command::new(program)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// Run a command and return its raw output without checking the exit
/// code — for callers that parse stdout themselves and treat a nonzero
/// status as "empty/absent" rather than a hard error (blkid, luksDump,
/// lsblk, `btrfs subvolume show`).
pub fn capture(program: &str, args: &[&str]) -> Output {
    Command::new(program)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .unwrap_or_else(|_| Output {
            status: ExitStatusExt::from_raw(-1),
            stdout: Vec::new(),
            stderr: Vec::new(),
        })
}
