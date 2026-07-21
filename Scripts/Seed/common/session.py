"""
common/session.py — tracks the active img per terminal session
Uses the terminal emulator PID as session key — stable for entire terminal lifetime,
shell-agnostic, works across fish/bash/zsh/any shell.
"""

import os
from lib.variables.general import *



def _proc_name(pid: int) -> str:
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except Exception:
        return ""


def _ppid(pid: int) -> int:
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except Exception:
        pass
    return 1


def _terminal_pid() -> int:
    """
    Walk up the process tree from current process.
    Return the PID of the terminal emulator or session root.
    """
    pid = os.getpid()
    last = pid
    while pid > 1:
        name = _proc_name(pid)
        if name in TERMINAL_NAMES:
            return pid
        last = pid
        pid  = _ppid(pid)
    # hit PID 1 — return the highest ancestor we found (the shell's parent)
    return last


def _session_key() -> str:
    return str(_terminal_pid())


def get_active() -> str:
    from common.errors import error
    key  = _session_key()
    path = f"{SESSIONS_BASE}/{key}"
    if not os.path.isfile(path):
        error("NO_SESSION", "no active img — run: sd select path/to/img")
    try:
        mnt = open(path).read().strip()
    except Exception:
        error("SESSION_READ_ERROR", "failed to read session file")
    if not os.path.isdir(mnt):
        error("SESSION_STALE", "active img is no longer mounted — run: sd select path/to/img")
    return mnt


def write_session(mnt: str) -> None:
    os.makedirs(SESSIONS_BASE, exist_ok=True)
    with open(f"{SESSIONS_BASE}/{_session_key()}", "w") as f:
        f.write(mnt)


def clear_session() -> None:
    path = f"{SESSIONS_BASE}/{_session_key()}"
    if os.path.isfile(path):
        os.remove(path)