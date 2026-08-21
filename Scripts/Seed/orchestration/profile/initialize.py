"""
orchestration/profile/initialize.py — initialize profile with data from layers
"""

import os
import shutil


def initialize_profile_from_layers(profile_path: str, layer_path: str, mount_path: str) -> None:
    """Initialize profile by copying pre-existing data from layer.

    If data exists at mount_path in the layer, copy it to profile.
    Only creates empty dirs for paths that don't exist in the layer.

    Args:
        profile_path: Path to the profile directory (e.g., profiles/n8n/default)
        layer_path: Path to the base layer (e.g., layers/base-ubuntu-22.04-xxx)
        mount_path: The mount point path (e.g., /root/.n8n)
    """
    # Ensure mount_path is absolute and remove leading slash for joining
    mount_path = mount_path.lstrip("/")

    # Source: check layer for existing data
    src = os.path.join(layer_path, mount_path)
    dst = os.path.join(profile_path, mount_path)

    # Create parent directories in profile
    os.makedirs(os.path.dirname(dst), exist_ok=True)

    # If data exists in layer, copy it; otherwise create empty directory
    if os.path.exists(src):
        if os.path.isdir(src):
            # Copy entire directory tree
            shutil.copytree(src, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns(".*"))
        else:
            # Copy single file
            shutil.copy2(src, dst)
    else:
        # Create empty directory for non-existent paths
        os.makedirs(dst, exist_ok=True)
