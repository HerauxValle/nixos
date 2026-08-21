"""
lib/privilege_helpers.py — Direct privilege operations wrapper
Replaces subprocess calls to sd-priv-iso with hardcoded safe operations.

This consolidates all privilege-escalated operations in one place with
hardened flags built-in, eliminating the need for external helpers.
"""

import subprocess
import os
from pathlib import Path

RUNTIME_DIR = Path("/var/lib/sd")


def mount_container_image_safe(image_hash: str, container_id: str) -> str:
    """
    Mount container image with hardened flags (ro,bind,nosuid,nodev,noexec,rprivate).
    Returns rootfs path on success.
    """
    image_path = RUNTIME_DIR / "images" / image_hash
    rootfs = RUNTIME_DIR / "containers" / container_id / "rootfs"

    # Pre-flight validation
    if not image_path.exists() or not image_path.is_file():
        raise ValueError(f"Image not found: {image_path}")
    if not rootfs.exists() or not rootfs.is_dir():
        raise ValueError(f"Container rootfs not found: {rootfs}")

    # Mount with restrictive flags (rprivate prevents propagation to host)
    result = subprocess.run(
        ["sudo", "mount", str(image_path), str(rootfs),
         "-o", "ro,bind,nosuid,nodev,noexec,rprivate"],
        capture_output=True, text=True, timeout=10
    )

    if result.returncode != 0:
        raise RuntimeError(f"Mount failed: {result.stderr}")

    return str(rootfs)


def setup_namespace_mounts(rootfs: str) -> None:
    """
    Set up pseudo-filesystems with hardened flags.
    Must be called after unshare to set up /proc, /sys, /dev, etc.
    """
    mounts = [
        # (source, target, fstype, opts)
        ("sysfs", "sys", "sysfs", "nodev,nosuid,noexec,rprivate"),
        ("devpts", "dev/pts", "devpts", "nodev,nosuid,noexec,rprivate,gid=5,mode=620"),
        ("tmpfs", "dev/shm", "tmpfs", "nodev,nosuid,noexec,rprivate,size=64m"),
        ("tmpfs", "tmp", "tmpfs", "nodev,nosuid,noexec,rprivate,size=512m"),
        ("tmpfs", "run", "tmpfs", "nodev,nosuid,noexec,rprivate,size=64m"),
    ]

    for src, target, fstype, opts in mounts:
        target_path = os.path.join(rootfs, target)
        os.makedirs(target_path, exist_ok=True)

        result = subprocess.run(
            ["sudo", "mount", "-t", fstype, "-o", opts, src, target_path],
            capture_output=True, timeout=10
        )

        if result.returncode != 0 and "already mounted" not in result.stderr.decode():
            raise RuntimeError(f"Mount {target} failed: {result.stderr}")

    # /proc with hidepid=2
    proc_path = os.path.join(rootfs, "proc")
    os.makedirs(proc_path, exist_ok=True)
    subprocess.run(
        ["sudo", "mount", "-t", "proc", "-o", "hidepid=2,rprivate",
         "proc", proc_path],
        capture_output=True, timeout=10
    )

    # /sys read-only
    sys_path = os.path.join(rootfs, "sys")
    subprocess.run(
        ["sudo", "mount", "-o", "remount,ro,nodev,nosuid,noexec,rprivate", sys_path],
        capture_output=True, timeout=10
    )


def create_minimal_dev(rootfs: str) -> None:
    """Create minimal /dev with only safe devices (null, zero, random, tty, etc)."""
    dev_dir = os.path.join(rootfs, "dev")
    os.makedirs(dev_dir, exist_ok=True)

    safe_devices = [
        ("null", "c", 1, 3, 0o666),
        ("zero", "c", 1, 5, 0o666),
        ("full", "c", 1, 7, 0o666),
        ("random", "c", 1, 8, 0o666),
        ("urandom", "c", 1, 9, 0o666),
        ("tty", "c", 5, 0, 0o666),
        ("ptmx", "c", 5, 2, 0o666),
    ]

    for name, dev_type, major, minor, mode in safe_devices:
        path = os.path.join(dev_dir, name)
        subprocess.run(
            ["sudo", "mknod", "-m", oct(mode)[2:], path, dev_type, str(major), str(minor)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5
        )
