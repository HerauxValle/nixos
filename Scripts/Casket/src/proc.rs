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

/// A *reserved but not created* unique temp path, deleted on drop if it
/// ends up existing. Used where cryptsetup itself needs to be the one
/// creating the file (`luksDump --dump-master-key --master-key-file`,
/// `luksFormat --header`) -- cryptsetup refuses to write into a file
/// that's already there (`Cannot open keyfile ... for write`), so this
/// only claims a name collision-free at reservation time, not the file
/// itself. Same "unique, cleaned up on drop, even on early `?` return"
/// shape as `TempKeyfile`, minus the create-and-write step.
pub struct TempOutPath {
    path: PathBuf,
}

impl TempOutPath {
    pub fn reserve(prefix: &str) -> Result<Self> {
        let dir = std::env::temp_dir();
        for _ in 0..8 {
            let path = dir.join(format!(".cas-{prefix}-{:016x}", rand::random::<u64>()));
            if !path.exists() {
                return Ok(TempOutPath { path });
            }
        }
        Err(CasError::new("could not reserve a temporary output path"))
    }

    pub fn path(&self) -> &std::path::Path {
        &self.path
    }

    /// Write secret-bearing bytes (a header, a volume key) into this
    /// path with mode 0600 from creation -- unlike a plain
    /// `std::fs::write`, which inherits the process umask (0644 under a
    /// typical 0022 umask, world-readable). Confirmed live 2026-08-17:
    /// every header/volume-key temp file staged during
    /// headerOffset/headerEncryption enable/disable/rotate/verify went
    /// through plain `std::fs::write` and landed world-readable on a
    /// real (non-tmpfs) filesystem.
    pub fn write_secure(&self, data: &[u8]) -> Result<()> {
        use std::io::Write;
        let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&self.path)?;
        f.write_all(data)?;
        Ok(())
    }

    /// Overwrite the file's content in place before it's removed, so an
    /// unlink doesn't leave secret-bearing bytes forensically recoverable
    /// from the underlying blocks. Best-effort: on the tmpfs case this is
    /// somewhat moot (nothing durable to recover), but on the real,
    /// disk-backed temp dir this codebase actually uses, it's the
    /// difference between "gone" and "still sitting in unallocated
    /// space." Ignores errors -- this runs from `Drop`, where there's no
    /// way to propagate a failure and the file may never have been
    /// written to in the first place (a bare `reserve()` that was never
    /// used).
    fn shred(&self) {
        if let Ok(meta) = std::fs::metadata(&self.path) {
            if let Ok(mut f) = std::fs::OpenOptions::new().write(true).open(&self.path) {
                use std::io::Write;
                let filler = vec![0u8; meta.len() as usize];
                let _ = f.write_all(&filler);
                let _ = f.sync_all();
            }
        }
    }
}

impl Drop for TempOutPath {
    fn drop(&mut self) {
        self.shred();
        let _ = std::fs::remove_file(&self.path);
    }
}

impl Drop for TempKeyfile {
    fn drop(&mut self) {
        if let Ok(meta) = std::fs::metadata(&self.path) {
            if let Ok(mut f) = std::fs::OpenOptions::new().write(true).open(&self.path) {
                use std::io::Write;
                let filler = vec![0u8; meta.len() as usize];
                let _ = f.write_all(&filler);
                let _ = f.sync_all();
            }
        }
        let _ = std::fs::remove_file(&self.path);
    }
}

/// Scopes the process umask to 0077 for the duration of a call that lets
/// *cryptsetup itself* create a secret-bearing file (`--master-key-file`,
/// `luksFormat --header`) -- `TempOutPath::reserve` only claims a
/// collision-free name, it never creates the file (cryptsetup refuses to
/// write into one that already exists), so there's no `OpenOptions::mode`
/// hook available the way there is for `write_secure`. `umask` is
/// process-wide and this codebase isn't multi-threaded around these
/// calls, so a save/restore guard is safe. Restores the prior umask on
/// drop unconditionally, including on an early `?` return past the
/// guard's scope.
pub struct UmaskGuard(libc::mode_t);

impl UmaskGuard {
    pub fn scoped_0077() -> Self {
        // umask(2) both sets and returns the previous mask in one call —
        // there's no separate "read only" form, so this doubles as the
        // save step.
        let prev = unsafe { libc::umask(0o077) };
        UmaskGuard(prev)
    }
}

impl Drop for UmaskGuard {
    fn drop(&mut self) {
        unsafe {
            libc::umask(self.0);
        }
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
