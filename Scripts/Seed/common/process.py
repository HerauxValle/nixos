"""
common/process.py — generic process tracker
Writes .toml files to img/.tmp/processes/ so sd close kills everything.
"""
from common.emit import emit

import os
import signal
import subprocess
import json



def _proc_dir() -> str | None:
    try:
        # Don't use get_active() which can call sys.exit() on stale sessions
        # Instead, manually check if session exists and is valid
        from lib.variables.general import SESSIONS_BASE
        from common.session import _session_key

        key = _session_key()
        path = f"{SESSIONS_BASE}/{key}"
        if not os.path.isfile(path):
            return None
        mnt = open(path).read().strip()
        if not os.path.isdir(mnt):
            return None  # session stale, but don't crash

        d = os.path.join(mnt, ".tmp", "processes")
        os.makedirs(d, exist_ok=True)
        return d
    except Exception:
        return None


def _write(name: str, pid: int, kind: str = "process", parent: str | None = None) -> None:
    d = _proc_dir()
    if not d:
        return
    data = {"name": name, "pid": pid, "kind": kind, "parent": parent or ""}
    with open(os.path.join(d, f"{name}.json"), "w") as f:
        json.dump(data, f)


def _read_all() -> list[dict]:
    d = _proc_dir()
    if not d:
        return []
    result = []
    for f in os.listdir(d):
        if not f.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, f)) as fp:
                result.append(json.load(fp))
        except Exception:
            pass
    return result


def track(pid: int, name: str, kind: str = "process", parent: str | None = None) -> None:
    """Register a PID for tracking. Will be killed on sd close."""
    _write(name, pid, kind, parent)
    emit("log", f"tracking pid {pid} as '{name}' ({kind})")


def untrack(name: str) -> None:
    """Remove a tracked process (e.g. after it exits cleanly)."""
    d = _proc_dir()
    if not d:
        return
    path = os.path.join(d, f"{name}.json")
    if os.path.isfile(path):
        os.remove(path)
        emit("log", f"untracked '{name}'")


def spawn(name: str, cmd: list[str], kind: str = "process",
          parent: str | None = None, **kwargs) -> subprocess.Popen:
    """
    Spawn a background process and track it automatically.
    Returns the Popen object.
    """
    proc = subprocess.Popen(cmd, **kwargs)
    track(proc.pid, name, kind, parent)
    return proc


def kill_all() -> None:
    """Kill all tracked processes. Called by sd close."""
    for p in _read_all():
        try:
            os.kill(p["pid"], signal.SIGTERM)
            emit("log", f"SIGTERM → {p['pid']} ({p['name']})")
        except ProcessLookupError:
            emit("log", f"pid {p['pid']} ({p['name']}) already dead")
        except Exception as e:
            emit("log", f"could not kill {p['name']}: {e}")


def list_tracked() -> list[dict]:
    """Return list of tracked processes with alive status."""
    result = []
    for p in _read_all():
        try:
            os.kill(p["pid"], 0)
            p["alive"] = True
        except ProcessLookupError:
            p["alive"] = False
        result.append(p)
    return result