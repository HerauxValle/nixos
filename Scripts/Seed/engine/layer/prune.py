"""
core/layer/prune.py — remove unreferenced layers and stopped containers
"""

from common.emit import emit

import os
import tomllib
import datetime

from orchestration.trash.manager import delete_subvol
from lib.variables.general import *



def _read_meta(path: str) -> dict:
    p = os.path.join(path, "meta.toml")
    if not os.path.isfile(p):
        return {}
    with open(p, "rb") as f:
        return tomllib.load(f)


def prune(mnt: str, all_stopped: bool = False) -> None:
    pruned = 0

    # prune zero-ref layers
    layers_dir = os.path.join(mnt, DIR_LAYERS)
    if os.path.isdir(layers_dir):
        for name in os.listdir(layers_dir):
            path = os.path.join(layers_dir, name)
            meta = _read_meta(path)
            refs = int(meta.get("refs", "0"))
            if refs == 0:
                emit("log", f"pruning layer {name}")
                delete_subvol(path, mnt)
                pruned += 1

    # prune stopped containers
    containers_dir = os.path.join(mnt, DIR_CONTAINERS)
    if os.path.isdir(containers_dir):
        for name in os.listdir(containers_dir):
            path   = os.path.join(containers_dir, name)
            meta   = _read_meta(path)
            status = meta.get("status", "stopped")
            if status == "stopped" and all_stopped:
                emit("log", f"pruning container {name}")
                rootfs = os.path.join(path, "rootfs")
                if os.path.isdir(rootfs):
                    delete_subvol(rootfs, mnt)
                import shutil
                shutil.rmtree(path, ignore_errors=True)
                pruned += 1

    emit("action", "pruned", f"{pruned} item(s)")