"""
core/layer/build.py — SDL builder
Two-layer cache: base (rootfs+deps) and app (base+install).
Content-addressed by section hash.
"""

from common.emit import emit

import os
import hashlib
import shlex
import subprocess
import tomllib

from engine.rootfs.pull   import pull, extract
from engine.rootfs.detect import detect, install_cmd, update_cmd
from orchestration.trash.manager import delete_subvol
from lib.variables.general import *
from lib.privilege import btrfs, chown, chroot, mount, umount



def _hash(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def _read_meta(path: str) -> dict:
    p = os.path.join(path, FILE_META)
    if not os.path.isfile(p):
        return {}
    with open(p, "rb") as f:
        return tomllib.load(f)


def _write_meta(path: str, meta: dict) -> None:
    with open(os.path.join(path, FILE_META), "w") as f:
        for k, v in meta.items():
            f.write(f'{k} = "{v}"\n')


def _run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def _create_subvol(path: str) -> None:
    btrfs("subvolume", "create", path)
    chown(os.getuid(), os.getgid(), path)


def _snapshot_subvol(src: str, dst: str) -> None:
    btrfs("subvolume", "snapshot", src, dst)
    chown(os.getuid(), os.getgid(), dst, recursive=True)


def _chroot(rootfs: str, cmd: list[str]) -> None:
    chroot(rootfs, cmd)


def _mount_pseudo(rootfs: str) -> None:
    for fs, target, fstype in [
        ("proc",    "proc", "proc"),
        ("sysfs",   "sys",  "sysfs"),
        ("devtmpfs","dev",  "devtmpfs"),
    ]:
        t = os.path.join(rootfs, target)
        os.makedirs(t, exist_ok=True)
        mount(fs, t, fstype=fstype, check=False)


def _umount_pseudo(rootfs: str) -> None:
    for target in ["dev", "sys", "proc"]:
        umount(os.path.join(rootfs, target))


def _write_resolv(rootfs: str) -> None:
    p = os.path.join(rootfs, "etc", "resolv.conf")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write("nameserver 1.1.1.1\nnameserver 8.8.8.8\n")


def _process_deps(deps: list[tuple[str, str]], pkg_manager: str) -> list[str]:
    """
    Process new-style deps (manager, args) tuples into shell commands.

    Args:
        deps: list of (manager_name, args) tuples from parse_deps()
        pkg_manager: detected package manager (apt, apk, etc)

    Returns:
        list of shell commands to execute in chroot
    """
    from builder.discovery import get_manager

    commands = []
    for manager_name, args in deps:
        try:
            manager = get_manager(manager_name)
            if not manager:
                emit("log", f"warning: unknown dependency manager '{manager_name}'")
                continue

            # Parse manager-specific args
            parsed = manager.parse(args)

            # Get install commands from manager
            install_cmds = manager.install(pkg_manager, parsed)

            # Special handling for 'pkg' manager: use system package manager
            if manager_name == "pkg":
                actual_cmd = install_cmd(pkg_manager, parsed["packages"])
                install_cmds = [" ".join(actual_cmd)] if actual_cmd else []

            commands.extend(install_cmds)
        except Exception as e:
            emit("log", f"error parsing {manager_name}: {e}")
            raise

    return commands


def build(svc, mnt: str) -> str:
    """Build SDL layers. Returns path to app layer subvol."""
    from parser.processing.types import BuildConfig
    cfg: BuildConfig = svc.build

    layers_dir   = os.path.join(mnt, DIR_LAYERS)
    os.makedirs(layers_dir, exist_ok=True)

    # Hash deps: convert new-style (manager, args) back to string for hashing
    deps_str = " ".join(f"{m}:{a}" for m, a in cfg.deps) if cfg.deps else ""
    deps_hash = _hash(deps_str)
    install_hash = _hash("\n".join(l.strip() for l in cfg.install if l.strip()))
    base_id      = f"base-{cfg.rootfs.replace(':', '-')}-{deps_hash}"
    app_id       = f"app-{base_id}-{install_hash}"
    base_path    = os.path.join(layers_dir, base_id)
    app_path     = os.path.join(layers_dir, app_id)

    # base layer
    base_complete = os.path.isdir(base_path) and os.path.isfile(os.path.join(base_path, FILE_META))
    if not base_complete:
        if os.path.isdir(base_path):
            emit("log", f"incomplete base layer — cleaning up")
            delete_subvol(base_path, mnt)
        emit("action", "building", f"base layer ({cfg.rootfs})")
        _create_subvol(base_path)
        try:
            tarball = pull(cfg.rootfs, mnt)
            extract(tarball, base_path)
            if cfg.deps:
                _write_resolv(base_path)
                pkg = detect(base_path)
                if not pkg:
                    from common.errors import error
                    error("NO_PKG_MANAGER", "could not detect package manager")
                emit("log", f"package manager: {pkg}")
                _mount_pseudo(base_path)
                try:
                    update = update_cmd(pkg)
                    if update:
                        _chroot(base_path, update)
                    # Process new-style deps (manager, args) into shell commands
                    deps_commands = _process_deps(cfg.deps, pkg)
                    for cmd in deps_commands:
                        _chroot(base_path, ["sh", "-c", cmd])
                    try:
                        _chroot(base_path, ["update-ca-certificates"])
                    except Exception:
                        pass
                finally:
                    _umount_pseudo(base_path)
            _write_meta(base_path, {
                "type": "base", "id": base_id,
                "rootfs": cfg.rootfs, "refs": "0"
            })
            emit("log", f"base layer built → {base_id}")
        except Exception:
            _umount_pseudo(base_path)
            emit("log", f"base layer failed — cleaning up")
            delete_subvol(base_path, mnt)
            raise
    else:
        emit("log", f"base layer cached → {base_id}")

    # app layer
    app_complete = os.path.isdir(app_path) and os.path.isfile(os.path.join(app_path, FILE_META))
    if not app_complete:
        if os.path.isdir(app_path):
            emit("log", f"incomplete app layer — cleaning up")
            delete_subvol(app_path, mnt)
        emit("action", "building", "app layer")
        _snapshot_subvol(base_path, app_path)
        try:
            if cfg.install:
                _write_resolv(app_path)
                _mount_pseudo(app_path)
                try:
                    # export env vars into install environment (shell-escaped)
                    env_exports = "\n".join(
                        f"export {shlex.quote(k)}={shlex.quote(v)}"
                        for k, v in svc.run.env.items() if v
                    )
                    script = env_exports + "\n" + "\n".join(cfg.install)
                    chroot(app_path, ["sh", "-c", script])
                finally:
                    _umount_pseudo(app_path)
            _write_meta(app_path, {
                "type": "app", "id": app_id,
                "base_id": base_id, "refs": "0"
            })
            emit("log", f"app layer built → {app_id}")
        except Exception:
            _umount_pseudo(app_path)
            emit("log", f"app layer failed — cleaning up")
            delete_subvol(app_path, mnt)
            raise
    else:
        emit("log", f"app layer cached → {app_id}")

    return app_path


def increment_refs(layer_path: str) -> None:
    meta = _read_meta(layer_path)
    meta["refs"] = str(int(meta.get("refs", "0")) + 1)
    _write_meta(layer_path, meta)


def decrement_refs(layer_path: str, mnt: str) -> None:
    meta = _read_meta(layer_path)
    refs = max(0, int(meta.get("refs", "1")) - 1)
    meta["refs"] = str(refs)
    _write_meta(layer_path, meta)
    if refs == 0:
        emit("log", f"layer {os.path.basename(layer_path)} unreferenced — queuing delete")
        delete_subvol(layer_path, mnt)