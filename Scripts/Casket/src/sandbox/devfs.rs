// &desc: "Minimal /dev for exec's sandbox -- null/zero/random/urandom/tty only, via bind-mounting the host's real device nodes rather than mknod. Real char-special mknod is refused inside a user namespace even as fake root; bind-mounting the equivalent host node sidesteps that and is what every rootless container runtime does for the same reason. Raw block device access from inside a sandbox would defeat the entire point, so nothing beyond this small set is exposed."
use std::ffi::CString;
use std::fs;
use std::io;
use std::path::Path;

const NODES: &[&str] = &["null", "zero", "random", "urandom", "tty"];

fn cstr(s: &str) -> io::Result<CString> {
    CString::new(s).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))
}

/// Populates `<target>` (the pre-pivot new-root's `dev/` subdirectory --
/// see `procfs::mount_proc`'s doc comment for why pre-pivot, not the
/// post-pivot `/dev`) with bind-mounted copies of the host's own device
/// nodes for just the names in `NODES`. Source paths are still `/dev/*`
/// on the host, since this runs before `pivot_root` changes what `/`
/// means for the calling process.
pub fn setup(target_dir: &Path) -> io::Result<()> {
    fs::create_dir_all(target_dir)?;
    for name in NODES {
        let target = target_dir.join(name);
        fs::write(&target, [])?; // bind-mount target must already exist as a file
        let src = cstr(&format!("/dev/{name}"))?;
        let dst = cstr(&target.to_string_lossy())?;
        let ret = unsafe { libc::mount(src.as_ptr(), dst.as_ptr(), std::ptr::null(), libc::MS_BIND, std::ptr::null()) };
        if ret != 0 {
            return Err(io::Error::last_os_error().into());
        }
    }
    Ok(())
}
