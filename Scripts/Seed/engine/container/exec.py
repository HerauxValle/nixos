"""
core/container/exec.py — run a command inside a running SDX
"""
from common.emit import emit

import os
import subprocess
import tomllib
from lib.variables.general import *
# Privilege operations removed; not used in this module




def _find_matching_containers(mnt: str, pattern: str) -> list[str]:
    """Find all containers matching the pattern."""
    import fnmatch
    cdir = os.path.join(mnt, DIR_CONTAINERS)
    if not os.path.isdir(cdir):
        return []
    return [name for name in os.listdir(cdir) if fnmatch.fnmatch(name, pattern)]


def exec_cmd(container_name: str, mnt: str, cmd: list[str], all_: bool = False) -> None:
    from common.errors import error
    from common.sanitize import safe_name
    if container_name and not all_ and "*" not in container_name:
        safe_name(container_name, "container")

    # Handle -all flag
    if all_:
        cdir = os.path.join(mnt, DIR_CONTAINERS)
        if not os.path.isdir(cdir):
            return
        for name in sorted(os.listdir(cdir)):
            path = os.path.join(cdir, name)
            if os.path.isdir(path):
                meta = _read_meta(path)
                if meta.get("status") == "running":
                    exec_cmd(name, mnt, cmd)
        return

    # Handle pattern matching
    if "*" in container_name:
        matching = _find_matching_containers(mnt, container_name)
        if not matching:
            error("NOT_FOUND", "no containers match pattern", container_name)
        for name in matching:
            safe_name(name, "container (matched)")
            meta = _read_meta(os.path.join(mnt, DIR_CONTAINERS, name))
            if meta.get("status") == "running":
                exec_cmd(name, mnt, cmd)
        return

    container_path = os.path.join(mnt, DIR_CONTAINERS, container_name)
    if not os.path.isdir(container_path):
        error("NOT_FOUND", "container not found", container_name)

    meta   = _read_meta(container_path)
    status = meta.get("status", "stopped")
    pid    = meta.get("pid", "")

    if status != "running" or not pid:
        from common.errors import error
        error("NOT_RUNNING", f"container '{container_name}' is not running")

    emit("log", f"exec in {container_name} (pid {pid}): {cmd}")
    # Use namespace symlinks directly (avoids pgrep TOCTOU race)
    from common.sanitize import safe_pid
    safe_pid(pid, "container PID (exec)")
    # nsenter -t PID opens /proc/PID/ns/* symlinks which are hold-open safe
    # even if PID dies after we read it; avoids child PID lookup race
    subprocess.run(["sudo", "nsenter", "-t", str(pid), "--all", "--"] + cmd,
                   close_fds=True, pass_fds=())


def _read_meta(path: str) -> dict:
    from common.sanitize import safe_toml_load
    return safe_toml_load(os.path.join(path, "meta.toml"))