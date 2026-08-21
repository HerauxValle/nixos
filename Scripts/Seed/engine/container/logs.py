"""
core/container/logs.py — stream or tail container logs
"""

from common.emit import emit

import os
import subprocess
import tomllib
from lib.variables.general import *



def _read_meta(path: str) -> dict:
    from common.sanitize import safe_toml_load
    return safe_toml_load(os.path.join(path, "meta.toml"))


def _find_matching_containers(mnt: str, pattern: str) -> list[str]:
    """Find all containers matching the pattern."""
    import fnmatch
    cdir = os.path.join(mnt, DIR_CONTAINERS)
    if not os.path.isdir(cdir):
        return []
    return [name for name in os.listdir(cdir) if fnmatch.fnmatch(name, pattern)]


def logs(container_name: str, mnt: str, follow: bool = False, lines: int = 50, all_: bool = False) -> None:
    from common.errors import error

    # Handle -all flag (show logs for all containers)
    if all_:
        cdir = os.path.join(mnt, DIR_CONTAINERS)
        if not os.path.isdir(cdir):
            return
        for name in sorted(os.listdir(cdir)):
            path = os.path.join(cdir, name)
            if os.path.isdir(path):
                logs(name, mnt, follow=follow, lines=lines)
        return

    # Handle pattern matching
    if "*" in container_name:
        matching = _find_matching_containers(mnt, container_name)
        if not matching:
            error("NOT_FOUND", "no containers match pattern", container_name)
        for name in matching:
            logs(name, mnt, follow=follow, lines=lines)
        return

    container_path = os.path.join(mnt, DIR_CONTAINERS, container_name)
    if not os.path.isdir(container_path):
        error("NOT_FOUND", "container not found", container_name)

    log_path = os.path.join(container_path, FILE_OUTPUT_LOG)
    if not os.path.isfile(log_path):
        emit("action", "logs", "no logs yet")
        return

    cmd = ["tail", f"-n{lines}"]
    if follow:
        cmd.append("-f")
    cmd.append(log_path)
    subprocess.run(cmd)