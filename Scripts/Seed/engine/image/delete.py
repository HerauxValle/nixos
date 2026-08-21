"""
core/img/delete.py — deletes a .img file
"""

from common.emit import emit

import os
import subprocess
import tomllib
from lib.variables.general import *




def _run(cmd: list[str]) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        from common.errors import error
        error("CMD_FAILED", f"{cmd[0]} {cmd[1]}", result.stderr.strip())
    return result


def _find_loop(img_path: str) -> str | None:
    result = subprocess.run(
        ["sudo", "losetup", "--list", "--output", "NAME,BACK-FILE", "--noheadings"],
        capture_output=True, text=True
    )
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and os.path.abspath(parts[1]) == os.path.abspath(img_path):
            return parts[0]
    return None


def _find_mnt(img_path: str) -> str | None:
    if not os.path.isdir(MNT_BASE):
        return None
    img_name = os.path.splitext(os.path.basename(img_path))[0]
    for d in os.listdir(MNT_BASE):
        mnt = f"{MNT_BASE}/{d}"
        meta_path = f"{mnt}/meta.toml"
        if not os.path.isfile(meta_path):
            continue
        try:
            with open(meta_path, "rb") as f:
                meta = tomllib.load(f)
            if meta.get("name") == img_name:
                return mnt
        except Exception:
            continue
    return None


def delete(img_path: str) -> None:
    from common.errors import error

    img_path = os.path.abspath(img_path)
    if not os.path.exists(img_path):
        error("IMG_NOT_FOUND", "image file not found", img_path)

    mnt = _find_mnt(img_path)
    errors = []
    if mnt:
        from engine.image.close import _unmount_containers, _kill_processes
        _kill_processes(mnt)
        _unmount_containers(mnt)

        if os.path.ismount(mnt):
            emit("log", f"unmounting {mnt}...")
            try:
                _run(["sudo", "umount", "-l", mnt])
            except Exception as e:
                errors.append(f"umount: {e}")
        try:
            with open(f"{mnt}/meta.toml", "rb") as f:
                meta = tomllib.load(f)
            mapper_name = meta.get("mapper")
            if mapper_name and os.path.exists(f"/dev/mapper/{mapper_name}"):
                emit("log", f"closing {mapper_name}...")
                try:
                    _run(["sudo", "cryptsetup", "close", mapper_name])
                except Exception as e:
                    errors.append(f"cryptsetup: {e}")
        except Exception:
            pass
        try:
            os.rmdir(mnt)
        except OSError:
            pass

    # Always detach loop devices even if earlier steps failed (R2)
    try:
        result = subprocess.run(
            ["sudo", "losetup", "--list", "--output", "NAME,BACK-FILE", "--noheadings"],
            capture_output=True, text=True
        )
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2:
                back = " ".join(parts[1:]).split(" (")[0]
                if os.path.abspath(back) == os.path.abspath(img_path):
                    emit("log", f"detaching {parts[0]}...")
                    subprocess.run(["sudo", "losetup", "-d", parts[0]],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        errors.append(f"losetup: {e}")

    if errors:
        emit("log", f"cleanup warnings: {'; '.join(errors)}")

    name = os.path.basename(img_path)
    if os.path.exists(img_path):
        os.remove(img_path)
    emit("action", "deleted", name)