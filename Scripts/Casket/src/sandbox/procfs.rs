// &desc: "Fresh /proc for exec's sandbox, mounted into the pre-pivot new-root directory. Must target that path -- not the post-pivot '/proc' -- confirmed against Scripts/Seed/helpers/sd-init.c (a known-working reference): mounting proc after pivot_root fails EPERM ('Mount too revealing', a real kernel check on unprivileged-userns proc mounts) even with MS_NOSUID|MS_NODEV|MS_NOEXEC set; mounting the identical call into the still-pre-pivot target path does not. MS_NOSUID|MS_NODEV|MS_NOEXEC are still required regardless -- procfs is kernel-flagged SB_I_USERNS_VISIBLE and refused outright without them from an unprivileged user namespace."
use std::ffi::CString;
use std::io;
use std::path::Path;

pub fn mount_proc(target: &Path) -> io::Result<()> {
    std::fs::create_dir_all(target)?;
    let src = CString::new("proc").unwrap();
    let target_c = CString::new(target.to_string_lossy().as_bytes()).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let fstype = CString::new("proc").unwrap();
    let flags = (libc::MS_NOSUID | libc::MS_NODEV | libc::MS_NOEXEC) as libc::c_ulong;
    let ret = unsafe { libc::mount(src.as_ptr(), target_c.as_ptr(), fstype.as_ptr(), flags, std::ptr::null()) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}
