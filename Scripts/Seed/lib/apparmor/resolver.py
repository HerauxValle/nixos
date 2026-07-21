"""
lib/apparmor/resolver.py — Minimal binary path resolver

Resolves entrypoint + interpreter + essential helpers.
Does NOT do package introspection (keeps it simple).

Pattern: small set of explicit resolutions, not fuzzy matching.
"""

import os
from common.emit import emit
from common.errors import error


def resolve_binaries(service, mount_path: str) -> list[str]:
    """Resolve minimal set of executable paths required at runtime.

    Resolves:
    1. Entrypoint binary (from run.config.entrypoint)
    2. Interpreter (if detected via shebang, e.g., /usr/bin/python3)
    3. Interpreter symlink targets (e.g., /usr/bin/python3 → /usr/bin/python3.11)
    4. Essential helpers: /bin/sh, /usr/bin/env

    Does NOT introspect package manager or resolve dependencies.
    Validates all paths are absolute + safe.

    Args:
        service: Parsed Service object
        mount_path: Container rootfs mount path

    Returns:
        Sorted list of executable paths (absolute, within container)

    Raises:
        error() on invalid path
    """
    binaries = set()

    # 1. Entrypoint binary
    entrypoint_full = service.run.config.get("entrypoint", "")
    if entrypoint_full:
        entrypoint_binary = entrypoint_full.split()[0]
        binaries.add(entrypoint_binary)

        # 2. Detect interpreter from shebang
        try:
            interpreter = _read_shebang(f"{mount_path}{entrypoint_binary}")
            if interpreter:
                binaries.add(interpreter)
                emit("log", f"[apparmor] Detected interpreter: {interpreter}")

                # 3. Resolve symlink targets (e.g., python3 → python3.11)
                try:
                    resolved = _resolve_symlink(f"{mount_path}{interpreter}")
                    if resolved != interpreter:
                        binaries.add(resolved)
                        emit("log", f"[apparmor] Resolved symlink: {interpreter} → {resolved}")
                except Exception:
                    pass  # Symlink resolution optional

        except Exception as e:
            emit("warn", f"[apparmor] Could not detect interpreter for {entrypoint_binary}: {e}")

    # 4. Essential helpers (always needed in container)
    binaries.update(["/bin/sh", "/usr/bin/env"])

    # Validate all paths
    for binary in binaries:
        if not binary:
            continue

        if not binary.startswith("/"):
            error("INVALID_EXECUTABLE", f"Executable must be absolute path: {binary}")

        if ".." in binary or binary.startswith("~"):
            error("INVALID_EXECUTABLE", f"Path traversal in executable: {binary}")

    emit("log", f"[apparmor] Resolved {len(binaries)} executables: {', '.join(sorted(binaries))}")

    return sorted(binaries)


def _read_shebang(path: str) -> str | None:
    """Read shebang from file.

    Safely reads only first line, extracts interpreter path.
    Returns interpreter path (absolute) or None if not found.

    Examples:
        "#!/usr/bin/python3" → "/usr/bin/python3"
        "#!/usr/bin/env python3" → "/usr/bin/env" (first arg only)
        No shebang → None
        Binary file → None

    Args:
        path: Full path to file (container rootfs + relative path)

    Returns:
        Interpreter path string or None
    """
    try:
        with open(path, "rb") as f:
            first_bytes = f.read(2)

            # Not a shebang
            if first_bytes != b"#!":
                return None

            # Rewind and read first line
            f.seek(0)
            first_line = f.readline()

            # Decode (ignore errors for binary data)
            try:
                text = first_line.decode("utf-8", errors="ignore").strip()
            except Exception:
                return None

            # Extract interpreter
            if not text.startswith("#!"):
                return None

            # Get first argument after #! (ignore options)
            interpreter = text[2:].strip().split()[0]

            # Validate: must be absolute path
            if interpreter and interpreter.startswith("/"):
                return interpreter

            return None

    except (FileNotFoundError, PermissionError, OSError):
        return None


def _resolve_symlink(path: str) -> str:
    """Resolve symlink to its target.

    Follows single-level symlink (e.g., /usr/bin/python3 → /usr/bin/python3.11).
    Returns original path if not a symlink.

    Args:
        path: File path (may or may not be a symlink)

    Returns:
        Resolved path or original path if not a symlink
    """
    try:
        if os.path.islink(path):
            return os.readlink(path)
        return path
    except (FileNotFoundError, OSError):
        return path
