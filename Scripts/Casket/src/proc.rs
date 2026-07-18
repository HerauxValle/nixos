// &desc: "Thin wrappers around std::process::Command — run-and-check, run-with-stdin, run-and-ignore, run-and-capture — plus the secure temp-file type used where a secret genuinely must touch disk."
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};

use crate::error::{CasError, Result};

/// A secret written to a uniquely-named, mode-0600, exclusively-created
/// temp file and deleted on drop (even on an early `?` return). Used
/// only where something genuinely needs the secret as a file on disk —
/// `luksAddKey`'s auth+new key pair (a single stdin stream can't carry
/// two), and the raw-block keyfile extraction in keyfile_mount.rs.
/// Every other cryptsetup call pipes its secret over stdin instead and
/// never touches disk at all.
pub struct TempKeyfile {
    path: PathBuf,
}

impl TempKeyfile {
    pub fn write(secret: &[u8]) -> Result<Self> {
        use std::io::Write;
        let dir = std::env::temp_dir();
        for _ in 0..8 {
            let path = dir.join(format!(".cas-key-{:016x}", rand::random::<u64>()));
            match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&path)
            {
                Ok(mut f) => {
                    f.write_all(secret)?;
                    return Ok(TempKeyfile { path });
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e.into()),
            }
        }
        Err(CasError::new("could not create a temporary keyfile"))
    }

    pub fn path(&self) -> &std::path::Path {
        &self.path
    }
}

impl Drop for TempKeyfile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

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
