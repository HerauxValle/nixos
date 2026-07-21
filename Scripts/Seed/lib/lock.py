"""
lib/lock.py — Flock-based instance locking to prevent concurrent sd corruption.
"""

import fcntl
import os


_held_locks = {}


def acquire_lock(name: str) -> None:
    """Acquire an exclusive flock. Exits if another sd instance holds it."""
    lock_path = f"/tmp/sd-{name}.lock"
    fd = open(lock_path, "w")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        fd.close()
        from common.errors import error
        error("LOCKED", f"another sd instance holds the '{name}' lock",
              "wait for it to finish or remove /tmp/sd-*.lock if stale")
    _held_locks[name] = fd


def release_lock(name: str) -> None:
    """Release a held lock."""
    fd = _held_locks.pop(name, None)
    if fd:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
            fd.close()
        except Exception:
            pass
