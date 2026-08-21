"""
lib/preflight.py — Pre-flight checks for required external binaries.
Called once before operations that need privileged tools.
"""

import shutil


# Only checked when the specific operation is about to run
REQUIRED_FOR_CONTAINER = ["btrfs", "nsenter", "unshare", "ip"]
REQUIRED_FOR_ENCRYPTION = ["cryptsetup", "losetup"]
REQUIRED_FOR_NETWORK = ["ip", "iptables"]


def check_binaries(binaries: list[str]) -> None:
    """Verify listed binaries exist on PATH. Exits with clear error if not."""
    missing = [b for b in binaries if not shutil.which(b)]
    if missing:
        from common.errors import error
        error("MISSING_DEPS", f"required binaries not found: {', '.join(missing)}",
              "install them or check your PATH")


def check_container_deps() -> None:
    check_binaries(REQUIRED_FOR_CONTAINER)


def check_encryption_deps() -> None:
    check_binaries(REQUIRED_FOR_ENCRYPTION)


def check_network_deps() -> None:
    check_binaries(REQUIRED_FOR_NETWORK)
