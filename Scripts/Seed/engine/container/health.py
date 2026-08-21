"""
core/container/health.py — health check polling
"""
from common.emit import emit

import os
import time
import socket
import subprocess



def _parse_duration(s: str) -> float:
    """Parse '5s', '1m', '30s' into seconds."""
    s = s.strip().lower()
    if s.endswith("m"):
        return float(s[:-1]) * 60
    if s.endswith("h"):
        return float(s[:-1]) * 3600
    return float(s.rstrip("s") or "5")


def check_port(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except Exception:
        return False


def check_cmd(container_pid: str, cmd: str) -> bool:
    try:
        from common.sanitize import safe_pid
        pid = safe_pid(container_pid, "health check PID")
        result = subprocess.run(
            ["sudo", "nsenter", "-t", str(pid), "--all",
             "--", "sh", "-c", cmd],
            capture_output=True, timeout=10
        )
        return result.returncode == 0
    except Exception:
        return False


def wait_healthy(health: dict, container_pid: str,
                 timeout_override: float = None) -> bool:
    """
    Poll health check until passing or timeout.
    Returns True if healthy, False if timed out.
    """
    if not health:
        return True

    interval = _parse_duration(health.get("interval", "5s"))
    timeout  = timeout_override or _parse_duration(health.get("timeout", "30s"))
    retries  = int(health.get("retries", 3))
    port     = health.get("port", "")
    cmd      = health.get("cmd", "")

    deadline   = time.time() + timeout
    consecutive = 0

    while time.time() < deadline:
        ok = False
        if port:
            ok = check_port("127.0.0.1", int(port))
        elif cmd:
            ok = check_cmd(container_pid, cmd)
        else:
            return True  # no check defined

        if ok:
            consecutive += 1
            if consecutive >= retries:
                emit("log", "health check passed")
                return True
        else:
            consecutive = 0

        time.sleep(interval)

    emit("log", "health check timed out")
    return False