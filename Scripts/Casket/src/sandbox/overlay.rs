// &desc: "OverlayFS mount for a layered rootfs environment (base=lower, upper=upper) -- mounted onto `target` from inside the sandbox's own already-unshared mount namespace (see mod.rs::run), so it's torn down automatically with the rest of the namespace on exit rather than lingering as a real host mount. Pure paths in, no vault/environment concept here -- that's commands::exec's job."
use std::ffi::CString;
use std::io;
use std::path::{Path, PathBuf};

/// `lower` (read-only base), `upper` (read-write, survives a base
/// update) and `work` (overlayfs's own scratch area -- must be empty,
/// on the same filesystem as `upper`, never touched by anything else)
/// merged onto `target`, which must already exist as a plain directory.
/// Owns its paths (not `&Path`) -- cheap, and avoids threading a
/// lifetime through every caller for three small path buffers.
pub struct Spec {
    pub lower: PathBuf,
    pub upper: PathBuf,
    pub work: PathBuf,
}

fn cstr(p: &Path) -> io::Result<CString> {
    CString::new(p.to_string_lossy().as_bytes()).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))
}

pub fn mount(target: &Path, spec: &Spec) -> io::Result<()> {
    std::fs::create_dir_all(&spec.work)?;

    let fstype = CString::new("overlay").unwrap();
    let target_c = cstr(target)?;
    let options = format!(
        "lowerdir={},upperdir={},workdir={}",
        spec.lower.to_string_lossy(),
        spec.upper.to_string_lossy(),
        spec.work.to_string_lossy(),
    );
    let options_c = cstr(Path::new(&options))?;

    let ret = unsafe { libc::mount(fstype.as_ptr(), target_c.as_ptr(), fstype.as_ptr(), 0, options_c.as_ptr() as *const libc::c_void) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}
