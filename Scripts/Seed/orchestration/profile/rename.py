"""
orchestration/profile/rename.py — rename a profile
"""

from common.emit import emit
from common.errors import error
import os
import subprocess
from orchestration.profile.create import _profile_path, _read_meta, _write_meta
from lib.privilege import mv


def rename_profile(container: str, old_name: str, new_name: str, mnt: str) -> None:
    """Rename a profile. Prevents renames that would break things."""
    old_path = _profile_path(mnt, container, old_name)
    new_path = _profile_path(mnt, container, new_name)

    if not os.path.isdir(old_path):
        error("NOT_FOUND", f"profile not found: {container}/{old_name}")

    if os.path.exists(new_path):
        error("PROFILE_EXISTS", f"profile already exists: {container}/{new_name}")

    # Check if old profile is active
    meta = _read_meta(old_path)
    if meta.get("active") == "true":
        error("PROFILE_ACTIVE", f"cannot rename active profile: {container}/{old_name}",
              "stop the container using this profile first")

    # Rename via subprocess (btrfs rename or mv)
    mv(old_path, new_path)

    # Update meta.toml with new name
    meta["name"] = new_name
    _write_meta(new_path, meta)

    emit("action", "renamed", f"{container}/{old_name} → {new_name}")
