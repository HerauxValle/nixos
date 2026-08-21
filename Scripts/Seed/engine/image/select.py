"""
core/img/select.py — mounts an existing .img and sets it as active session
"""

from common.emit import emit

import os
import subprocess
import tomllib
import datetime
from lib.variables.general import *
from lib.privilege import losetup, mount, chown




def _run(cmd: list[str], input: str = None) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, input=input, capture_output=True, text=True)
    if result.returncode != 0:
        from common.errors import error
        error("CMD_FAILED", f"{cmd[0]} {cmd[1]}", result.stderr.strip())
    return result


def _img_name(path: str) -> str:
    return os.path.splitext(os.path.basename(path))[0]


def _write_session(mnt: str) -> None:
    from common.session import write_session
    write_session(mnt)


def _already_mounted(path: str) -> str | None:
    if not os.path.isdir(MNT_BASE):
        return None
    result = losetup("--list", "--output", "NAME,BACK-FILE", "--noheadings")
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and os.path.abspath(parts[1]) == os.path.abspath(path):
            for d in os.listdir(MNT_BASE):
                mnt       = f"{MNT_BASE}/{d}"
                meta_path = f"{mnt}/meta.toml"
                if not os.path.isfile(meta_path):
                    continue
                try:
                    with open(meta_path, "rb") as f:
                        meta = tomllib.load(f)
                    if meta.get("name") == _img_name(path):
                        return mnt
                except Exception:
                    continue
    return None


def _search_img(name: str, depth: int) -> list[str]:
    """Search home dir up to depth for name.img files with valid headers."""
    from engine.image.header import read_header
    home    = os.path.expanduser("~")
    matches = []
    target  = f"{name}.img"

    def _walk(d: str, current_depth: int) -> None:
        if current_depth > depth:
            return
        try:
            for entry in os.scandir(d):
                if entry.is_file() and entry.name == target:
                    # Only add if header is valid (no backward compat)
                    if read_header(entry.path) is not None:
                        matches.append(entry.path)
                elif entry.is_dir() and not entry.name.startswith("."):
                    _walk(entry.path, current_depth + 1)
        except PermissionError:
            pass

    _walk(home, 1)
    return matches



def _wipe_tmp(mnt: str) -> None:
    import shutil
    tmp = os.path.join(mnt, ".tmp")
    os.makedirs(tmp, exist_ok=True)
    for item in os.listdir(tmp):
        path = os.path.join(tmp, item)
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    os.makedirs(os.path.join(tmp, "processes"), exist_ok=True)
    os.makedirs(os.path.join(tmp, "tables"), exist_ok=True)
    emit("log", "wiped .tmp/ and ensured .tmp/processes/ .tmp/tables/")


def _is_direct_path(path: str) -> bool:
    """True if path looks like a real path, not just a name."""
    return "/" in path or path.endswith(".img") or os.path.exists(path)


def select(path: str, depth: int = DEFAULT_SEARCH_DEPTH) -> None:
    from common.errors import error

    # if not a direct path — search for it
    if not _is_direct_path(path):
        matches = _search_img(path, depth)
        if not matches:
            error("NOT_FOUND", f"no img named '{path}' found", f"searched home at depth {depth}")
        if len(matches) > 1:
            error("AMBIGUOUS", f"multiple imgs named '{path}' found",
                  *matches,
                  "specify full path to select one")
        path = matches[0]
        emit("log", f"found → {path}")

    path = os.path.abspath(path)
    if not os.path.exists(path):
        error("NOT_FOUND", "img file not found", path)
    if not path.endswith(".img"):
        error("INVALID_PATH", "path must point to a .img file", path)

    mnt = _already_mounted(path)
    if mnt:
        emit("log", f"already mounted → {mnt}")
        _wipe_tmp(mnt)
        _write_session(mnt)
        emit("action", "selected", _img_name(path))
        return

    ts          = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    mapper_name = f"sd_{ts}"
    mapper      = f"/dev/mapper/{mapper_name}"
    mnt         = f"{MNT_BASE}/{ts}"

    result = _run(["sudo", "losetup", "--find", "--show", path])
    loop   = result.stdout.strip()
    emit("log", f"loop device → {loop}")

    # Try unlock with UNLOCK_PRIORITY order
    from lib.encryption.luks import try_unlock_priority
    os.makedirs(MNT_BASE, exist_ok=True)
    if not try_unlock_priority(path, mapper_name, mnt):
        from common.errors import error
        error("UNLOCK_FAILED", "could not unlock LUKS image",
              "check passphrase/keyfiles or ensure image is properly initialized")
    emit("log", f"opened LUKS → {mapper_name}")

    os.makedirs(mnt, exist_ok=True)
    _run(["sudo", "mount", mapper, mnt])
    _run(["sudo", "chown", f"{os.getuid()}:{os.getgid()}", mnt])
    emit("log", f"mounted → {mnt}")

    with open(f"{mnt}/meta.toml", "rb") as f:
        meta = tomllib.load(f)
    with open(f"{mnt}/meta.toml", "w") as f:
        f.write(
            f'name    = "{meta["name"]}"\n'
            f'created = "{meta["created"]}"\n'
            f'mapper  = "{mapper_name}"\n'
            f'mnt     = "{mnt}"\n'
            f'hash    = "{meta.get("hash", "")}"\n'
        )

    from common.config import regenerate_missing
    regenerate_missing(mnt)
    _wipe_tmp(mnt)
    _write_session(mnt)
    emit("action", "selected", _img_name(path))