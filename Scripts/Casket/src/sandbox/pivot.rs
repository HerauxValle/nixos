// &desc: "mount-tree privatization + bind + pivot_root + oldroot cleanup for exec's sandbox. pivot_root over chroot deliberately -- chroot only changes path resolution, doesn't touch the mount tree, and a process with CAP_SYS_CHROOT can escape via a pre-opened directory fd + fchdir. pivot_root inside a real private mount namespace, followed by unmounting the old root, removes that escape path structurally."
use std::ffi::CString;
use std::io;
use std::path::Path;

fn cstr(p: &Path) -> io::Result<CString> {
    CString::new(p.to_string_lossy().as_bytes()).map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))
}

/// `mount("none", "/", MS_REC | MS_PRIVATE)` -- detaches the whole
/// mount tree from host propagation. Skipping this is the classic
/// mistake that lets an in-sandbox mount leak back to the real host.
pub fn make_root_private() -> io::Result<()> {
    let none = CString::new("none").unwrap();
    let root = CString::new("/").unwrap();
    let ret = unsafe {
        libc::mount(
            none.as_ptr(),
            root.as_ptr(),
            std::ptr::null(),
            (libc::MS_REC | libc::MS_PRIVATE) as libc::c_ulong,
            std::ptr::null(),
        )
    };
    if ret != 0 {
        return Err(io::Error::last_os_error().into());
    }
    Ok(())
}

/// `pivot_root` requires its target to already be a mount point, not
/// just a plain directory -- bind-mounting it onto itself is the
/// standard way to satisfy that without needing a second real
/// filesystem. `MS_REC` is required, not optional: a plain `MS_BIND`
/// self-mount fails with EINVAL the moment the target directory
/// already contains any nested mount of its own (confirmed empirically
/// -- e.g. once a rootfs environment has an overlay mounted under it).
pub fn bind_mount_self(path: &Path) -> io::Result<()> {
    let c = cstr(path)?;
    let ret = unsafe { libc::mount(c.as_ptr(), c.as_ptr(), std::ptr::null(), libc::MS_BIND | libc::MS_REC, std::ptr::null()) };
    if ret != 0 {
        return Err(io::Error::last_os_error().into());
    }
    // A bind mount can't set NOSUID/NODEV in the same mount() call --
    // needs a separate MS_REMOUNT|MS_BIND pass. Locking these on the
    // new root itself, not just on /proc, is real defense-in-depth
    // (matches what bubblewrap does to its own root) even though it
    // wasn't the fix for the "Mount too revealing" EPERM -- that turned
    // out to be about mount timing relative to pivot_root, see
    // procfs::mount_proc's doc comment.
    let remount_flags = (libc::MS_BIND | libc::MS_REMOUNT | libc::MS_NOSUID | libc::MS_NODEV) as libc::c_ulong;
    let ret = unsafe { libc::mount(std::ptr::null(), c.as_ptr(), std::ptr::null(), remount_flags, std::ptr::null()) };
    if ret != 0 {
        return Err(io::Error::last_os_error().into());
    }
    Ok(())
}

/// `pivot_root(new_root, new_root/<old_root_relative>)`, `chdir("/")`,
/// then `umount2(old, MNT_DETACH)` and removes the now-empty mountpoint
/// directory. `old_root_relative` must be a path *under* `new_root`
/// (e.g. `.casket/oldroot` for a real vault, or a throwaway dir for the
/// standalone PoC) -- `pivot_root` requires the old-root mountpoint to
/// live inside the new root.
pub fn pivot(new_root: &Path, old_root_relative: &Path) -> io::Result<()> {
    let old_root_abs = new_root.join(old_root_relative);
    std::fs::create_dir_all(&old_root_abs)?;

    let new_c = cstr(new_root)?;
    let old_c = cstr(&old_root_abs)?;
    let ret = unsafe { libc::syscall(libc::SYS_pivot_root, new_c.as_ptr(), old_c.as_ptr()) };
    if ret != 0 {
        return Err(io::Error::last_os_error().into());
    }

    std::env::set_current_dir("/")?;

    let old_root_from_new_root = Path::new("/").join(old_root_relative);
    let old_c2 = cstr(&old_root_from_new_root)?;
    let ret = unsafe { libc::umount2(old_c2.as_ptr(), libc::MNT_DETACH) };
    if ret != 0 {
        return Err(io::Error::last_os_error().into());
    }
    let _ = std::fs::remove_dir(&old_root_from_new_root);
    Ok(())
}
