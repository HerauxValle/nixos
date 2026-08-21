"""
core/container/delete.py — delete a stopped container
"""
from common.emit import emit

import os
import shutil
import subprocess

from engine.layer.build   import decrement_refs
from orchestration.trash.manager import delete_subvol


def _find_matching_containers(mnt: str, pattern: str) -> list[str]:
    """Find all containers matching the pattern."""
    import fnmatch
    cdir = os.path.join(mnt, "containers")
    if not os.path.isdir(cdir):
        return []
    return [name for name in os.listdir(cdir) if fnmatch.fnmatch(name, pattern)]


def delete(container_name: str, mnt: str, all_: bool = False) -> None:
    from common.errors import error
    from common.sanitize import safe_name
    if container_name and not all_ and "*" not in container_name:
        safe_name(container_name, "container")

    # Handle -all flag
    if all_:
        cdir = os.path.join(mnt, "containers")
        if not os.path.isdir(cdir):
            return
        for name in sorted(os.listdir(cdir)):
            path = os.path.join(cdir, name)
            if os.path.isdir(path):
                meta = {}
                meta_path = os.path.join(path, "meta.toml")
                if os.path.isfile(meta_path):
                    with open(meta_path, "rb") as f:
                        import tomllib
                        meta = tomllib.load(f)
                if meta.get("status") != "running":
                    delete(name, mnt)
        return

    # Handle pattern matching
    if "*" in container_name:
        matching = _find_matching_containers(mnt, container_name)
        if not matching:
            error("NOT_FOUND", "no containers match pattern", container_name)
        for name in matching:
            path = os.path.join(mnt, "containers", name)
            meta = {}
            meta_path = os.path.join(path, "meta.toml")
            if os.path.isfile(meta_path):
                with open(meta_path, "rb") as f:
                    import tomllib
                    meta = tomllib.load(f)
            if meta.get("status") != "running":
                delete(name, mnt)
        return

    container_path = os.path.join(mnt, "containers", container_name)
    if not os.path.isdir(container_path):
        error("NOT_FOUND", "container not found", container_name)

    import tomllib
    meta_path = os.path.join(container_path, "meta.toml")
    meta = {}
    if os.path.isfile(meta_path):
        with open(meta_path, "rb") as f:
            meta = tomllib.load(f)

    if meta.get("status") == "running":
        error("STILL_RUNNING", "container is running — stop it first",
              container_name)

    # decrement layer refs
    layer = meta.get("layer", "")
    if layer:
        layer_path = os.path.join(mnt, "layers", layer)
        if os.path.isdir(layer_path):
            decrement_refs(layer_path, mnt)

    # delete rootfs subvol
    rootfs = os.path.join(container_path, "rootfs")
    if os.path.isdir(rootfs):
        delete_subvol(rootfs, mnt)

    # remove container dir
    shutil.rmtree(container_path, ignore_errors=True)
    emit("log", f"deleted container {container_name}")
    emit("action", "deleted", container_name)