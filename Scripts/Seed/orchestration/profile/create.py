"""
core/profile/create.py — SDP (profile) management
Profiles are namespaced: profiles/<service>/<name>/
"""

from common.emit import emit

import os
import subprocess
import tomllib
import datetime
from lib.variables.general import *
from lib.variables.general import DIR_PROFILES
from lib.privilege import umount




def _run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, capture_output=True)


def _profile_path(mnt: str, svc_name: str, name: str) -> str:
    return os.path.join(mnt, DIR_PROFILES, svc_name, name)


def _write_meta(path: str, meta: dict) -> None:
    with open(os.path.join(path, "meta.toml"), "w") as f:
        for k, v in meta.items():
            f.write(f'{k} = "{v}"\n')


def _read_meta(path: str) -> dict:
    p = os.path.join(path, "meta.toml")
    if not os.path.isfile(p):
        return {}
    with open(p, "rb") as f:
        return tomllib.load(f)


def create_profile(svc_name: str, name: str, mnt: str,
                   nodatacow: bool = False) -> str:
    """Create SDP subvol at profiles/<svc>/<name>/. Returns path."""
    path = _profile_path(mnt, svc_name, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)

    if os.path.isdir(path):
        emit("log", f"profile exists → {svc_name}/{name}")
        return path

    _run(["sudo", "btrfs", "subvolume", "create", path])
    _run(["sudo", "chown", f"{os.getuid()}:{os.getgid()}", path])

    if nodatacow:
        subprocess.run(["sudo", "chattr", "+C", path], capture_output=True)

    try:
        subprocess.run(["setfacl", "-m", f"u:{os.getuid()}:rwx", path],
                       capture_output=True)
    except Exception:
        pass

    _write_meta(path, {
        "name":       name,
        "service":    svc_name,
        "created":    datetime.datetime.now().isoformat(),
        "nodatacow":  str(nodatacow).lower(),
        "host_uid":   str(os.getuid()),
        "mount_mode": "exclusive",
        "refs":       "0",
        "default":    "false",
        "active":     "false",
    })
    emit("log", f"profile created → {svc_name}/{name}")
    return path


def ensure_profiles(svc_name: str, storage_nodes, mnt: str, layer_path: str = "") -> None:
    """Create all profiles declared in a service's [storage] block.

    First creates a "default" profile if it doesn't exist, sets it as default.
    Then creates additional profiles from storage_nodes.

    If layer_path is provided, initializes each profile with data from the layer
    (copies existing data, creates empty dirs for missing paths).
    """
    from orchestration.profile.initialize import initialize_profile_from_layers

    svc_dir = os.path.join(mnt, DIR_PROFILES, svc_name)
    os.makedirs(svc_dir, exist_ok=True)

    # Ensure "default" profile exists and is marked as default
    default_path = _profile_path(mnt, svc_name, "default")
    if not os.path.isdir(default_path):
        create_profile(svc_name, "default", mnt)

    # Initialize default profile from layer if not already initialized
    if layer_path and os.path.isdir(layer_path):
        # Check if profile is newly created (no files in it besides meta.toml)
        default_contents = [f for f in os.listdir(default_path) if f != "meta.toml"]
        if not default_contents:
            # Initialize from layer for all storage nodes
            for node in storage_nodes:
                initialize_profile_from_layers(default_path, layer_path, node.mount)

    # Mark "default" as the default profile
    meta = _read_meta(default_path)
    if meta.get("default") != "true":
        meta["default"] = "true"
        _write_meta(default_path, meta)

    # Create additional profiles from storage nodes
    for node in storage_nodes:
        # node.name may be nested like "models/checkpoints"
        parts = node.name.split("/")
        profile_path = _profile_path(mnt, svc_name, node.name)
        if not os.path.isdir(profile_path):
            create_profile(svc_name, node.name, mnt)
            # Initialize newly created profile from layer
            if layer_path and os.path.isdir(layer_path):
                initialize_profile_from_layers(profile_path, layer_path, node.mount)


def mount_profile(svc_name: str, name: str, mnt: str,
                  rootfs: str, mount_path: str,
                  readonly: bool = False) -> None:
    """Bind mount a profile into container rootfs."""
    from common.sanitize import safe_path_within
    src = _profile_path(mnt, svc_name, name)
    dst = safe_path_within(rootfs, mount_path.lstrip("/"), "mount_path")

    meta = _read_meta(src)
    if meta.get("mount_mode") == "exclusive" and \
       int(meta.get("refs", "0")) > 0 and not readonly:
        from common.errors import error
        error("PROFILE_BUSY",
              f"profile '{svc_name}/{name}' is exclusively mounted")

    os.makedirs(dst, exist_ok=True)
    opts = ["--bind"]
    if readonly:
        opts.append("--read-only")
    subprocess.run(["sudo", "mount"] + opts + [src, dst], check=True)
    emit("log", f"mounted {svc_name}/{name} → {mount_path}")


def unmount_profile(rootfs: str, mount_path: str) -> None:
    from common.sanitize import safe_path_within
    dst = safe_path_within(rootfs, mount_path.lstrip("/"), "mount_path")
    subprocess.run(umount(dst), capture_output=True)