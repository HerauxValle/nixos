"""
lib/sandboxing/landlock/compat.py — Kernel version detection for Landlock

Landlock requires Linux 5.13+. Detects kernel capability gracefully.
No errors on older kernels — just returns False and caller handles fallback.
"""

import os
from common.emit import emit


def check_landlock_available() -> bool:
    """Check if kernel supports Landlock sandboxing.

    Detects Landlock via /proc/sys/kernel/landlock.syscall
    (available on Linux 5.13+).

    Returns:
        True if Landlock available, False otherwise
    """
    landlock_file = "/proc/sys/kernel/landlock.syscall"

    try:
        with open(landlock_file, "r") as f:
            value = f.read().strip()
            available = value == "1"
            if available:
                emit("log", "[landlock] Kernel supports Landlock")
            else:
                emit("log", "[landlock] Kernel doesn't support Landlock (check /proc/sys/kernel/landlock.syscall)")
            return available
    except FileNotFoundError:
        emit("log", "[landlock] Kernel too old or Landlock disabled (no /proc/sys/kernel/landlock.syscall)")
        return False
    except (OSError, PermissionError) as e:
        emit("warn", f"[landlock] Could not check kernel support: {e}")
        return False


def get_kernel_version() -> tuple[int, int, int] | None:
    """Get kernel version as (major, minor, patch) tuple.

    Reads from /proc/version or uname.
    Returns None if unable to determine.
    """
    try:
        with open("/proc/version", "r") as f:
            # Format: "Linux version 5.13.0-51-generic (buildd@...) ..."
            parts = f.read().split()
            version_str = parts[2]  # "5.13.0-51-generic"

            # Extract major.minor.patch
            base = version_str.split("-")[0]  # "5.13.0"
            numbers = base.split(".")

            if len(numbers) >= 3:
                return (int(numbers[0]), int(numbers[1]), int(numbers[2]))
            elif len(numbers) == 2:
                return (int(numbers[0]), int(numbers[1]), 0)

        return None
    except (FileNotFoundError, ValueError, IndexError):
        return None
