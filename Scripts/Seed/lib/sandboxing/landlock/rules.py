"""
lib/sandboxing/landlock/rules.py — Map SecuritySpec to Landlock rules

Converts SecuritySpec constraints to Landlock rule objects.
Landlock is a hierarchical allow-list filesystem access control:
  - Allow specific paths for read/write/execute
  - Deny everything else by default

Maps SecuritySpec fields to Landlock rule types:
  - writable_paths → LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_MAKE_REG
  - read_only_paths → LANDLOCK_ACCESS_FS_READ_FILE
  - executables → LANDLOCK_ACCESS_FS_EXECUTE
"""

from dataclasses import dataclass
from common.emit import emit


# Landlock access control flags (from linux/landlock.h)
# These are the kernel's access mask values for filesystem operations
LANDLOCK_ACCESS_FS_EXECUTE = 1 << 0      # Permission to execute
LANDLOCK_ACCESS_FS_WRITE_FILE = 1 << 1   # Permission to write to file
LANDLOCK_ACCESS_FS_READ_FILE = 1 << 2    # Permission to read file
LANDLOCK_ACCESS_FS_READ_DIR = 1 << 3     # Permission to list directory
LANDLOCK_ACCESS_FS_REMOVE = 1 << 4       # Permission to remove file/dir
LANDLOCK_ACCESS_FS_MAKE_CHAR = 1 << 5    # Permission to create char device
LANDLOCK_ACCESS_FS_MAKE_REG = 1 << 6     # Permission to create regular file
LANDLOCK_ACCESS_FS_MAKE_DIR = 1 << 7     # Permission to create directory


@dataclass
class LandlockRule:
    """Single Landlock rule: allow certain operations on a path."""

    path: str          # Filesystem path (absolute)
    access: int        # Bitmask of LANDLOCK_ACCESS_FS_* flags
    recursive: bool    # True = allow on path and children

    def __repr__(self) -> str:
        access_names = []
        if self.access & LANDLOCK_ACCESS_FS_EXECUTE:
            access_names.append("execute")
        if self.access & LANDLOCK_ACCESS_FS_WRITE_FILE:
            access_names.append("write")
        if self.access & LANDLOCK_ACCESS_FS_READ_FILE:
            access_names.append("read")
        if self.access & LANDLOCK_ACCESS_FS_MAKE_REG:
            access_names.append("make_file")
        if self.access & LANDLOCK_ACCESS_FS_MAKE_DIR:
            access_names.append("make_dir")

        recursive_marker = "/**" if self.recursive else ""
        access_str = "+".join(access_names) if access_names else "none"

        return f"LandlockRule({self.path}{recursive_marker} → {access_str})"


def build_rules_from_spec(spec) -> list[LandlockRule]:
    """Build Landlock rules from SecuritySpec.

    Creates hierarchical allow-list for:
    - Read-only system paths
    - Writable storage paths
    - Executable binaries
    - Network (if enabled)

    Args:
        spec: SecuritySpec instance

    Returns:
        List of LandlockRule objects
    """
    rules = []

    emit("log", "[landlock] Building rules from SecuritySpec")

    # 1. Read-only system paths
    # Maps SecuritySpec.read_only_paths to read-only filesystem rules
    for path in spec.read_only_paths:
        rules.append(LandlockRule(
            path=path,
            access=LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR,
            recursive=True
        ))

    # 2. Executable paths
    # Apps need to execute binaries
    for exe_path in spec.executables:
        rules.append(LandlockRule(
            path=exe_path,
            access=LANDLOCK_ACCESS_FS_EXECUTE | LANDLOCK_ACCESS_FS_READ_FILE,
            recursive=False
        ))

    # 3. Writable storage paths
    # Allow full read/write/create on storage directories
    for storage_key, mount_path in spec.writable_paths.items():
        rules.append(LandlockRule(
            path=mount_path,
            access=(LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR |
                   LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_MAKE_REG |
                   LANDLOCK_ACCESS_FS_MAKE_DIR | LANDLOCK_ACCESS_FS_REMOVE),
            recursive=True
        ))

    # 4. Temporary directories (if allowed by preset)
    if spec.allow_tmp:
        for tmp_path in ["/tmp", "/var/tmp", "/run"]:
            rules.append(LandlockRule(
                path=tmp_path,
                access=(LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR |
                       LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_MAKE_REG |
                       LANDLOCK_ACCESS_FS_MAKE_DIR | LANDLOCK_ACCESS_FS_REMOVE),
                recursive=True
            ))

    # 5. /var handling (preset-dependent)
    if spec.allow_var == "all":
        rules.append(LandlockRule(
            path="/var",
            access=(LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR |
                   LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_MAKE_REG |
                   LANDLOCK_ACCESS_FS_MAKE_DIR | LANDLOCK_ACCESS_FS_REMOVE),
            recursive=True
        ))
    elif spec.allow_var == "log":
        rules.append(LandlockRule(
            path="/var/log",
            access=(LANDLOCK_ACCESS_FS_READ_FILE | LANDLOCK_ACCESS_FS_READ_DIR |
                   LANDLOCK_ACCESS_FS_WRITE_FILE | LANDLOCK_ACCESS_FS_MAKE_REG |
                   LANDLOCK_ACCESS_FS_MAKE_DIR),
            recursive=True
        ))

    emit("log", f"[landlock] Built {len(rules)} rules")

    return rules
