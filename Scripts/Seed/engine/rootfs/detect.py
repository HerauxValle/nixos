"""
core/rootfs/detect.py — detect package manager inside a rootfs
"""

import os
from lib.variables.general import *




def detect(rootfs_path: str) -> str | None:
    """
    Detect package manager in a rootfs directory.
    Returns pkg manager name or None.
    """
    for _, binary, name in PKG_MANAGERS:
        if os.path.isfile(f"{rootfs_path}{binary}"):
            return name
    return None


def install_cmd(pkg_manager: str, packages: list[str]) -> list[str]:
    """Return install command for given package manager."""
    cmds = {
        "apt":    ["apt-get", "install", "-y", "--no-install-recommends"] + packages,
        "pacman": ["pacman", "-S", "--noconfirm"] + packages,
        "apk":    ["apk", "add", "--no-cache"] + packages,
        "dnf":    ["dnf", "install", "-y"] + packages,
        "yum":    ["yum", "install", "-y"] + packages,
        "zypper": ["zypper", "install", "-y"] + packages,
    }
    return cmds.get(pkg_manager, [])


def update_cmd(pkg_manager: str) -> list[str]:
    """Return package list update command."""
    cmds = {
        "apt":    ["apt-get", "update", "-qq"],
        "pacman": ["pacman", "-Sy", "--noconfirm"],
        "apk":    ["apk", "update"],
        "dnf":    ["dnf", "check-update"],
        "yum":    ["yum", "check-update"],
        "zypper": ["zypper", "refresh"],
    }
    return cmds.get(pkg_manager, [])