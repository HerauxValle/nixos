"""
core/img/close.py — unmounts and closes a .img
"""

from common.emit import emit

import os
import subprocess
import tomllib




import signal
import shutil
from lib.variables.general import *
from lib.privilege import findmnt, umount, cryptsetup, losetup, fuser


def _kill_processes(mnt: str) -> None:
    """Kill all tracked processes via common/process."""
    from common.process import kill_all
    kill_all()


def _wipe_tmp(mnt: str) -> None:
    tmp = os.path.join(mnt, ".tmp")
    if not os.path.isdir(tmp):
        return
    for item in os.listdir(tmp):
        path = os.path.join(tmp, item)
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    emit("log", "wiped .tmp/")


def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        from common.errors import error
        error("CMD_FAILED", f"{cmd[0]} {cmd[1]}", result.stderr.strip())
    return result


def _find_mnt_by_name(name: str) -> str | None:
    if not os.path.isdir(MNT_BASE):
        return None
    for d in os.listdir(MNT_BASE):
        mnt = f"{MNT_BASE}/{d}"
        meta_path = f"{mnt}/meta.toml"
        if not os.path.isfile(meta_path):
            continue
        try:
            with open(meta_path, "rb") as f:
                meta = tomllib.load(f)
            if meta.get("name") == name:
                return mnt
        except Exception:
            continue
    return None


def _find_loop_for_mapper(mapper_name: str) -> str | None:
    """Find the loop device backing a dm-crypt mapper."""
    dm_path = f"/sys/block/dm-*/slaves"
    import glob as g
    for slaves_dir in g.glob(f"/sys/block/*/dm/name"):
        try:
            if open(slaves_dir).read().strip() == mapper_name:
                block_dir = os.path.dirname(os.path.dirname(slaves_dir))
                for slave in os.listdir(os.path.join(block_dir, "slaves")):
                    if slave.startswith("loop"):
                        return f"/dev/{slave}"
        except Exception:
            pass
    return None


def _cleanup_orphaned(mnt: str) -> None:
    """Clean up mapper/loop devices for an already-unmounted img."""
    ts = os.path.basename(mnt)
    mapper_name = f"sd_{ts}"
    mapper = f"/dev/mapper/{mapper_name}"
    loop = _find_loop_for_mapper(mapper_name)
    if os.path.exists(mapper):
        cryptsetup("close", mapper_name, check=False)
    if loop:
        losetup("-d", loop, check=False)
    try:
        os.rmdir(mnt)
    except OSError:
        pass


def _unmount_containers(mnt: str) -> None:
    """Unmount all bind mounts inside containers before closing img."""
    containers_dir = os.path.join(mnt, "containers")
    if not os.path.isdir(containers_dir):
        return
    for name in os.listdir(containers_dir):
        rootfs = os.path.join(containers_dir, name, "rootfs")
        if not os.path.isdir(rootfs):
            continue
        # get all submounts sorted deepest first
        result = subprocess.run(
            ["sudo", "findmnt", "--raw", "--noheadings",
             "-o", "TARGET", "--submounts", rootfs],
            capture_output=True, text=True
        )
        targets = [t.strip() for t in result.stdout.splitlines() if t.strip()]
        for t in sorted(targets, key=len, reverse=True):
            umount(t)
        emit("log", f"unmounted container {name}")


def _kill_mount_users(mnt: str) -> None:
    """Kill any processes using the mount point (prevents umount hangs)."""
    fuser("-km", mnt)


def _close_one(mnt: str) -> None:
    meta_path = f"{mnt}/meta.toml"
    if not os.path.isfile(meta_path):
        emit("log", f"meta.toml missing for {mnt} — cleaning up orphaned devices")
        _cleanup_orphaned(mnt)
        return

    with open(meta_path, "rb") as f:
        meta = tomllib.load(f)

    _kill_processes(mnt)
    _unmount_containers(mnt)
    try:
        from engine.network.manager import delete_bridge, free_subnet
        delete_bridge(mnt)
        free_subnet(mnt)
    except Exception as e:
        emit("log", f"network cleanup: {e}")
    _wipe_tmp(mnt)

    mapper_name = meta["mapper"]
    mapper      = f"/dev/mapper/{mapper_name}"

    # Find the loop device BEFORE unmounting (sysfs info disappears after close)
    loop = _find_loop_for_mapper(mapper_name)

    if os.path.ismount(mnt):
        emit("log", f"unmounting {mnt}...")
        _kill_mount_users(mnt)
        umount(mnt)
        try:
            os.rmdir(mnt)
        except OSError:
            pass

    if os.path.exists(mapper):
        emit("log", f"closing {mapper_name}...")
        cryptsetup("close", mapper_name, check=False)

    # Detach only the loop device for THIS image (not all)
    if loop:
        losetup("-d", loop, check=False)

    # Clear session
    from common.session import clear_session
    clear_session()


def close(name: str) -> None:
    mnt = _find_mnt_by_name(name)
    if not mnt:
        from common.errors import error
        error("NOT_MOUNTED", f"no mounted img found with name '{name}'")
    _close_one(mnt)
    emit("action", "closed", name)


def close_active() -> None:
    """Close the currently selected (active) image."""
    from common.session import get_active
    mnt = get_active()
    meta_path = f"{mnt}/meta.toml"
    name = "unknown"
    try:
        with open(meta_path, "rb") as f:
            name = tomllib.load(f).get("name", name)
    except Exception:
        pass
    _close_one(mnt)
    emit("action", "closed", name)


def close_all() -> None:
    if not os.path.isdir(MNT_BASE):
        emit("action", "info", "nothing mounted")
        return
    mnts = [f"{MNT_BASE}/{d}" for d in os.listdir(MNT_BASE)
            if os.path.isdir(f"{MNT_BASE}/{d}")]
    if not mnts:
        emit("action", "info", "nothing mounted")
        return
    names = []
    for mnt in mnts:
        try:
            with open(f"{mnt}/meta.toml", "rb") as f:
                meta = tomllib.load(f)
            names.append(meta.get("name", os.path.basename(mnt)))
        except Exception:
            names.append(os.path.basename(mnt))
        _close_one(mnt)
    # clear all stale sessions
    from common.session import clear_session
    clear_session()
    emit("action", "closed", ", ".join(names))