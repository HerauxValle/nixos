"""
core/container/list.py — list all containers with status and info
"""

from common.emit import emit

import os
import tomllib
import datetime

from ui.table    import table, TABLE_SECTION_KEY
from lib.variables.colors import c, DEFAULT, DEFAULT_SUCCESS, DEFAULT_WARN, BRED, BBLACK, CYAN
from lib.variables.general import *




def _read_meta(path: str) -> dict:
    from common.sanitize import safe_toml_load
    return safe_toml_load(os.path.join(path, "meta.toml"))


def _pid_alive(pid: str) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


def _fmt_time(iso: str) -> str:
    try:
        dt   = datetime.datetime.fromisoformat(iso)
        diff = datetime.datetime.now() - dt
        s    = int(diff.total_seconds())
        if s < 60:    return f"{s}s ago"
        if s < 3600:  return f"{s // 60}m ago"
        if s < 86400: return f"{s // 3600}h ago"
        return f"{s // 86400}d ago"
    except Exception:
        return iso


def list_containers(mnt: str) -> None:

    containers_dir = os.path.join(mnt, DIR_CONTAINERS)
    if not os.path.isdir(containers_dir):
        emit("action", "containers", "none")
        return

    entries = sorted(os.listdir(containers_dir))

    # clean up containers without meta.toml (incomplete builds)
    for name in entries[:]:
        path = os.path.join(containers_dir, name)
        if os.path.isdir(path) and not os.path.isfile(os.path.join(path, "meta.toml")):
            emit("log", f"incomplete container: {name}, removing")
            try:
                import shutil
                shutil.rmtree(path, ignore_errors=True)
            except Exception:
                pass
            entries.remove(name)

    if not entries:
        emit("action", "containers", "none")
        return

    # determine external blueprints dir once for origin detection
    _ext_bp_dir: str | None = None
    try:
        from orchestration.settings import get_external_blueprints_dir
        _ext_bp_dir = get_external_blueprints_dir()
    except Exception:
        pass

    def _blueprint_origin(service: str) -> str:
        internal_dir = os.path.join(mnt, DIR_BLUEPRINTS)
        if os.path.isdir(internal_dir):
            for f in os.listdir(internal_dir):
                if os.path.splitext(f)[0] == service:
                    return "internal"
        if _ext_bp_dir and os.path.isdir(_ext_bp_dir):
            for f in os.listdir(_ext_bp_dir):
                if os.path.splitext(f)[0] == service:
                    return "external"
        return "-"

    rows = []
    for name in entries:
        path = os.path.join(containers_dir, name)
        if not os.path.isdir(path):
            continue
        meta    = _read_meta(path)
        pid     = meta.get("pid", "")
        status  = meta.get("status", "unknown")
        alive   = _pid_alive(pid) if pid else False

        # reconcile status with actual pid
        if status == "running" and not alive:
            status = "exited"
        elif alive:
            status = "running"

        layer   = meta.get("layer", "-") or "-"
        created = _fmt_time(meta.get("created", ""))
        service = meta.get("service", "-")
        origin  = _blueprint_origin(service)

        rows.append({
            "name":    name,
            "service": service,
            "origin":  origin,
            "status":  status,
            "pid":     pid or "-",
            "layer":   layer,
            "created": created,
        })

    emit("table", rows, type="status", indicator_col="status")