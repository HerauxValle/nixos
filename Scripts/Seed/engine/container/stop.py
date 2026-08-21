"""
core/container/stop.py — stop a running SDX container
"""

from common.emit import emit

import os
import signal
import subprocess
import json
import tomllib

from engine.layer.build import decrement_refs
from lib.variables.general import *
from lib.privilege import findmnt, umount



def _read_meta(container_path: str) -> dict:
    from common.sanitize import safe_toml_load
    return safe_toml_load(os.path.join(container_path, "meta.toml"))


def _write_status(container_path: str, status: str) -> None:
    meta      = _read_meta(container_path)
    meta["status"] = status
    meta["pid"]    = ""
    with open(os.path.join(container_path, "meta.toml"), "w") as f:
        for k, v in meta.items():
            f.write(f'{k} = "{v}"\n')


def _kill_cgroup(cgroup_path: str) -> None:
    procs = os.path.join(cgroup_path, "cgroup.procs")
    if not os.path.isfile(procs):
        return
    try:
        with open(procs) as f:
            for pid in f.read().split():
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
    except Exception:
        pass


def _cleanup_mounts(rootfs: str) -> None:
    result = findmnt("--raw", "--noheadings", "-o", "TARGET", "--submounts", rootfs)
    targets = [t.strip() for t in result.stdout.splitlines() if t.strip()]
    for t in reversed(targets):
        umount(t)


def _match_pattern(container_name: str, pattern: str) -> bool:
    """Check if container_name matches the pattern (with * wildcards)."""
    import fnmatch
    return fnmatch.fnmatch(container_name, pattern)


def _find_matching_containers(mnt: str, pattern: str) -> list[str]:
    """Find all containers matching the pattern."""
    cdir = os.path.join(mnt, DIR_CONTAINERS)
    if not os.path.isdir(cdir):
        return []
    return [name for name in os.listdir(cdir) if _match_pattern(name, pattern)]


def stop(container_name: str, mnt: str, force: bool = False, all_: bool = False) -> None:
    from common.errors import error

    # Handle -all flag
    if all_:
        cdir = os.path.join(mnt, DIR_CONTAINERS)
        if not os.path.isdir(cdir):
            return
        for name in os.listdir(cdir):
            path = os.path.join(cdir, name)
            if os.path.isdir(path):
                meta = _read_meta(path)
                if meta.get("status") == "running":
                    stop(name, mnt, force=force)
        return

    # Handle pattern matching (*, *pattern, pattern*, *pattern*)
    if "*" in container_name:
        matching = _find_matching_containers(mnt, container_name)
        if not matching:
            error("NOT_FOUND", "no containers match pattern", container_name)
        for name in matching:
            path = os.path.join(mnt, DIR_CONTAINERS, name)
            if os.path.isdir(path):
                meta = _read_meta(path)
                if meta.get("status") == "running":
                    stop(name, mnt, force=force)
        return

    # Normal single container stop
    container_path = os.path.join(mnt, DIR_CONTAINERS, container_name)
    if not os.path.isdir(container_path):
        error("NOT_FOUND", "container not found", container_name)

    meta = _read_meta(container_path)
    status = meta.get("status", "stopped")
    pid = meta.get("pid", "")
    cgroup = meta.get("cgroup", "")

    if status == "stopped" and not force:
        emit("action", "already stopped", container_name)
        return

    if pid:
        try:
            os.kill(int(pid), signal.SIGTERM)
            emit("log", f"SIGTERM → {pid}")
        except (ProcessLookupError, ValueError):
            pass

    if cgroup:
        _kill_cgroup(cgroup)
        try:
            os.rmdir(cgroup)
        except OSError:
            pass

    rootfs = os.path.join(container_path, "rootfs")
    _cleanup_mounts(rootfs)

    layer = meta.get("layer", "")
    if layer:
        layer_path = os.path.join(mnt, "layers", layer)
        if os.path.isdir(layer_path):
            decrement_refs(layer_path, mnt)

    _write_status(container_path, "stopped")

    # network teardown
    container_ip = meta.get("ip", "")
    port_str     = meta.get("port", "")
    if container_ip:
        try:
            from engine.network.veth    import teardown_veth
            from engine.network.forward import kill_proxy, del_port_forward, parse_port
            teardown_veth(container_name)
            if port_str:
                for ps in (port_str if isinstance(port_str, list) else [port_str]):
                    hp, cp, proto = parse_port(str(ps))
                    del_port_forward(mnt, hp, container_ip, cp, proto)
                    kill_proxy(container_name, hp)
        except Exception as e:
            emit("log", f"network teardown: {e}")

    try:
        from engine.network.manager import free_container_ip
        free_container_ip(mnt, container_name)
    except Exception: pass

    from common.process import untrack
    untrack(container_name)
    emit("action", "stopped", container_name)


def cleanup_stale(mnt: str) -> None:
    """Scan containers, clean up dead PIDs and incomplete builds."""
    cdir = os.path.join(mnt, DIR_CONTAINERS)
    if not os.path.isdir(cdir):
        return
    for name in os.listdir(cdir):
        path   = os.path.join(cdir, name)
        meta   = _read_meta(path)
        status = meta.get("status", "stopped")
        pid    = meta.get("pid", "")

        # clean up incomplete builds stuck in "starting" (no pid)
        if status == "starting" and not pid:
            emit("log", f"incomplete build: {name}, removing")
            import shutil
            try:
                shutil.rmtree(path, ignore_errors=True)
            except Exception:
                pass
            continue

        if status == "running" and pid:
            try:
                os.kill(int(pid), 0)
            except (ProcessLookupError, ValueError):
                emit("log", f"stale: {name} (pid {pid} dead)")
                stop(name, mnt, force=True)
                from common.process import untrack
                untrack(name)