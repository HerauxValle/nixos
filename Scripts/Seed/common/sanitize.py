"""
common/sanitize.py — Input validation for user-supplied names/paths.
Prevents path traversal and injection via untrusted CLI arguments.
"""

import os
import re
import subprocess
import tomllib


def safe_name(name: str, label: str = "name") -> str:
    """
    Validate a user-supplied name (container, preset, slot, blueprint, etc.).
    Rejects path separators, null bytes, and traversal patterns.
    Returns the name unchanged if safe, otherwise raises error.
    """
    from common.errors import error

    if not name:
        error("INVALID_NAME", f"{label} cannot be empty")

    if "\x00" in name:
        error("INVALID_NAME", f"{label} contains null byte")

    if "/" in name or "\\" in name:
        error("INVALID_NAME", f"{label} contains path separator", name)

    if name in (".", "..") or ".." in name:
        error("INVALID_NAME", f"{label} contains path traversal", name)

    if len(name) > 255:
        error("INVALID_NAME", f"{label} too long (max 255)")

    return name


def safe_pid(pid, label: str = "PID") -> int:
    """
    Validate a PID value. Must be a positive integer within kernel range.
    Verifies the process actually exists via /proc.
    """
    from common.errors import error
    try:
        p = int(pid)
    except (TypeError, ValueError):
        error("INVALID_PID", f"{label} is not a valid integer", str(pid))
    if p <= 0:
        error("INVALID_PID", f"{label} must be positive", str(p))
    if p > 4194304:  # kernel pid_max upper bound
        error("INVALID_PID", f"{label} exceeds kernel maximum", str(p))
    if not os.path.isdir(f"/proc/{p}"):
        error("INVALID_PID", f"{label} does not exist (no /proc/{p})")
    return p


def safe_path_within(base: str, user_part: str, label: str = "path") -> str:
    """
    Join base + user_part and verify the result is within base.
    Prevents path traversal via symlinks or ../ sequences.
    """
    from common.errors import error

    joined = os.path.join(base, user_part)
    resolved = os.path.realpath(joined)
    base_resolved = os.path.realpath(base)

    if not resolved.startswith(base_resolved + os.sep) and resolved != base_resolved:
        error("PATH_TRAVERSAL", f"{label} escapes base directory", user_part)

    return joined


def safe_toml_load(path: str) -> dict:
    """Load a TOML file with graceful handling of corruption."""
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except tomllib.TOMLDecodeError:
        from common.emit import emit
        emit("log", f"warning: corrupted metadata: {path}")
        return {}


def check_btrfs(path: str) -> None:
    """Verify path is on a btrfs filesystem. Exits with clear error if not."""
    result = subprocess.run(
        ["stat", "-f", "-c", "%T", path],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        from common.errors import error
        error("FS_CHECK_FAILED", f"could not determine filesystem type for {path}")
    if "btrfs" not in result.stdout.strip().lower():
        from common.errors import error
        error("WRONG_FS", "btrfs required for snapshot operations",
              f"{path} is on {result.stdout.strip()}")
