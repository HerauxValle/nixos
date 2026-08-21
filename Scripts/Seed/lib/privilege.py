"""
lib/privilege.py — privilege escalation via sd-priv and sd-priv-iso helpers
ONLY semantic APIs with structured inputs. Zero pass-through functions.
"""

import os
import subprocess
import json
import fcntl
from pathlib import Path

HELPER_GENERAL = Path("/usr/local/lib/sd/priv/sd-priv")
HELPER_ISOLATED = Path("/usr/local/lib/sd/priv/sd-priv-iso")
SD_INIT = Path("/usr/local/lib/sd/priv/sd-init")
RUNTIME_DIR = Path("/var/lib/sd")
LOOPDEV_STATE = RUNTIME_DIR / "state" / "loopdevices.json"
HELPER_TIMEOUT = 60


def has_sd_init() -> bool:
    """Check if sd-init binary is available (required for container init)."""
    return SD_INIT.exists() and os.access(SD_INIT, os.X_OK)


def _has_helper(helper: Path) -> bool:
    """Check if helper is available and executable."""
    return helper.exists() and os.access(helper, os.X_OK)


def _priv_general(op: str, *args: str, check: bool = True, input_text: str = "") -> subprocess.CompletedProcess:
    """Execute via general helper (safe, data-driven operations)."""
    if _has_helper(HELPER_GENERAL):
        full_cmd = ["sudo", str(HELPER_GENERAL), op] + list(args)
    else:
        # Fallback: unpack operation to direct command (degrades to direct sudo)
        # Format: category:operation → map to direct command
        parts = op.split(":")
        if len(parts) == 2:
            category, cmd = parts
            if category == "own" and cmd == "chown":
                if len(args) < 3:
                    raise ValueError(f"chown requires 3 args (uid, gid, path), got {len(args)}")
                full_cmd = ["sudo", "chown", f"{args[0]}:{args[1]}", args[2]]
            elif category == "sys" and cmd == "mkdir":
                if len(args) < 1:
                    raise ValueError("mkdir requires a path argument")
                full_cmd = ["sudo", "mkdir", "-p", args[0]]
            elif category == "sys" and cmd == "mv":
                if len(args) < 2:
                    raise ValueError("mv requires src and dst arguments")
                full_cmd = ["sudo", "mv", args[0], args[1]]
            elif category == "fs" and cmd == "findmnt":
                if len(args) < 1:
                    raise ValueError("findmnt requires a path argument")
                full_cmd = ["sudo", "findmnt", args[0]]
            elif category == "blk" and cmd == "blkid":
                if len(args) < 1:
                    raise ValueError("blkid requires a device argument")
                full_cmd = ["sudo", "blkid", args[0]]
            else:
                raise ValueError(f"Unknown operation: {op}")
        else:
            raise ValueError(f"Invalid operation format: {op}")

    kwargs = {"timeout": HELPER_TIMEOUT, "check": check, "capture_output": True, "text": True}
    if input_text:
        kwargs["input"] = input_text

    return subprocess.run(full_cmd, **kwargs)


def _priv_isolated(op: str, *args: str, check: bool = True, input_text: str = "", interactive: bool = False) -> subprocess.CompletedProcess:
    """Execute via isolated helper (high-risk operations with hardcoded flags)."""
    if not _has_helper(HELPER_ISOLATED):
        from common.errors import error
        error("HELPER_MISSING",
              f"sd-priv-iso helper not found at {HELPER_ISOLATED}",
              "install with: ./install.sh --install --enable-root")

    full_cmd = ["sudo", str(HELPER_ISOLATED), op] + list(args)
    kwargs = {"timeout": HELPER_TIMEOUT, "check": check}
    if not interactive:
        kwargs.update({"capture_output": True, "text": True})
        if input_text:
            kwargs["input"] = input_text

    return subprocess.run(full_cmd, **kwargs)


# ============================================================================
# Loop Device Lifecycle Management (with atomic locking)
# ============================================================================

def _load_loopdev_state() -> dict:
    """Load loop device state from disk (with file locking)."""
    lockfile = LOOPDEV_STATE.parent / ".loopdevices.lock"
    try:
        lockfile.parent.mkdir(parents=True, exist_ok=True)
        # Use flock to prevent concurrent access
        with open(lockfile, "w") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_SH)  # Shared lock for read
            try:
                if LOOPDEV_STATE.exists():
                    with open(LOOPDEV_STATE) as f:
                        state = json.load(f)
                else:
                    state = {}
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        return state
    except (json.JSONDecodeError, IOError, OSError):
        return {}


def _save_loopdev_state(state: dict) -> None:
    """Save loop device state to disk (with file locking)."""
    lockfile = LOOPDEV_STATE.parent / ".loopdevices.lock"
    try:
        LOOPDEV_STATE.parent.mkdir(parents=True, exist_ok=True)
        with open(lockfile, "w") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)  # Exclusive lock for write
            try:
                with open(LOOPDEV_STATE, "w") as f:
                    json.dump(state, f, indent=2)
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
    except (IOError, OSError):
        pass  # Non-fatal: state file write failure


def _track_loopdev(container_id: str, image_hash: str, loopdev: str) -> None:
    """Track loop device attachment for container."""
    state = _load_loopdev_state()
    state[container_id] = {"image_hash": image_hash, "loopdev": loopdev}
    _save_loopdev_state(state)


def _untrack_loopdev(container_id: str) -> None:
    """Untrack loop device for container."""
    state = _load_loopdev_state()
    state.pop(container_id, None)
    _save_loopdev_state(state)


def _get_loopdev(container_id: str) -> str:
    """Get loop device path for container."""
    state = _load_loopdev_state()
    if container_id not in state:
        raise ValueError(f"No loop device tracked for container {container_id}")
    return state[container_id]["loopdev"]


# ============================================================================
# FILESYSTEM OPERATIONS
# ============================================================================

def mount_container_image(image_hash: str, container_id: str, check: bool = True) -> subprocess.CompletedProcess:
    """Mount container image (read-only, safe flags hardcoded)."""
    return _priv_isolated("fs:mount_image", image_hash, container_id, check=check)


def umount_container(container_id: str, check: bool = False) -> subprocess.CompletedProcess:
    """Unmount container rootfs."""
    return _priv_isolated("fs:umount_container", container_id, check=check)


def btrfs_subvol_create(container_id: str, check: bool = True) -> subprocess.CompletedProcess:
    """Create btrfs subvolume for container."""
    return _priv_isolated("fs:btrfs_subvol_create", container_id, check=check)


def btrfs_subvol_delete(container_id: str, check: bool = True) -> subprocess.CompletedProcess:
    """Delete btrfs subvolume for container."""
    return _priv_isolated("fs:btrfs_subvol_delete", container_id, check=check)


def findmnt(path: str, check: bool = False) -> subprocess.CompletedProcess:
    """Find mount points (read-only)."""
    return _priv_general("fs:findmnt", path, check=check)


def blkid(device: str, check: bool = True) -> subprocess.CompletedProcess:
    """Get block device info (read-only)."""
    return _priv_general("blk:blkid", device, check=check)


# ============================================================================
# BLOCK DEVICE OPERATIONS (with lifecycle tracking)
# ============================================================================

def losetup_attach(image_hash: str, container_id: str, check: bool = True) -> str:
    """
    Attach image to loop device and track association.
    Returns: loop device path (e.g., /dev/loop0)
    """
    result = _priv_isolated("blk:losetup_attach", image_hash, check=check)
    loopdev = result.stdout.strip()
    _track_loopdev(container_id, image_hash, loopdev)
    return loopdev


def losetup_detach(container_id: str, check: bool = True) -> subprocess.CompletedProcess:
    """Detach loop device from container (uses tracked state)."""
    loopdev = _get_loopdev(container_id)
    result = _priv_isolated("blk:losetup_detach", container_id, check=check)
    _untrack_loopdev(container_id)
    return result


# ============================================================================
# OWNERSHIP OPERATIONS
# ============================================================================

def chown(uid: int, gid: int, path: str, check: bool = True) -> subprocess.CompletedProcess:
    """Change ownership (must be under /var/lib/sd)."""
    return _priv_general("own:chown", str(uid), str(gid), path, check=check)


# ============================================================================
# NETWORK OPERATIONS
# ============================================================================

def veth_create(container_id: str, check: bool = True) -> subprocess.CompletedProcess:
    """Create veth pair for container."""
    return _priv_isolated("net:veth_create", container_id, check=check)


def veth_cleanup(container_id: str, check: bool = True) -> subprocess.CompletedProcess:
    """Delete veth pair for container."""
    return _priv_isolated("net:veth_cleanup", container_id, check=check)


# ============================================================================
# PROCESS/NAMESPACE OPERATIONS
# ============================================================================

def unshare_container(container_id: str, command: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    """
    Execute in new namespaces (hardcoded: -U -P -N -i -u --mount-proc).
    Command must be safe (no shell metacharacters, no absolute paths).
    Args are optional additional arguments for the command.
    """
    return _priv_isolated("proc:unshare_container", container_id, command, *args, check=check, interactive=True)


# ============================================================================
# SYSTEM OPERATIONS
# ============================================================================

def mkdir(path: str, check: bool = False) -> subprocess.CompletedProcess:
    """Create directory (mode always 0755, must be under /var/lib/sd)."""
    return _priv_general("sys:mkdir", path, check=check)


def mv(src: str, dst: str, check: bool = True) -> subprocess.CompletedProcess:
    """Move file (both paths must be under /var/lib/sd)."""
    return _priv_general("sys:mv", src, dst, check=check)


# ============================================================================
# INTERNAL COMPATIBILITY WRAPPERS (UNSAFE — for existing codebase only)
# ============================================================================
# These are retained ONLY for backward compatibility with existing code.
# DO NOT USE for new code. These functions accept arbitrary flags and
# are only safe because they're called internally with hardcoded arguments.

def btrfs(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Raw btrfs (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", "btrfs"] + list(args),
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def losetup(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Raw losetup (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", "losetup"] + list(args),
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def cryptsetup(op: str, *args: str, check: bool = True, input_text: str = "") -> subprocess.CompletedProcess:
    """Raw cryptsetup (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", "cryptsetup", op] + list(args),
        capture_output=True, text=True, input=input_text or None,
        timeout=HELPER_TIMEOUT, check=check
    )


def mkfs(fstype: str, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Raw mkfs (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", f"mkfs.{fstype}"] + list(args),
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def mount(src: str, dst: str, fstype: str = "", opts: str = "", bind: bool = False, check: bool = True) -> subprocess.CompletedProcess:
    """Raw mount (internal use only, existing code compatibility)."""
    args = []
    if bind:
        args.append("--bind")
    if fstype:
        args.extend(["-t", fstype])
    if opts:
        args.extend(["-o", opts])
    args.extend([src, dst])
    return subprocess.run(
        ["sudo", "mount"] + args,
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def umount(path: str, lazy: bool = True, check: bool = False) -> subprocess.CompletedProcess:
    """Raw umount (internal use only, existing code compatibility)."""
    args = ["-l"] if lazy else []
    args.append(path)
    return subprocess.run(
        ["sudo", "umount"] + args,
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def chroot(rootfs: str, cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """Raw chroot (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", "chroot", rootfs] + cmd,
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def ip(*args: str, check: bool = False) -> subprocess.CompletedProcess:
    """Raw ip (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", "ip"] + list(args),
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def iptables(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Raw iptables (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", "iptables"] + list(args),
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


def fuser(*args: str, check: bool = False) -> subprocess.CompletedProcess:
    """Raw fuser (internal use only, existing code compatibility)."""
    return subprocess.run(
        ["sudo", "fuser"] + list(args),
        capture_output=True, text=True, timeout=HELPER_TIMEOUT, check=check
    )


