"""
orchestration/profile/delete.py — delete a profile
"""

from common.emit import emit
from common.errors import error
import os
import subprocess
from orchestration.profile.create import _profile_path, _read_meta
from lib.privilege import btrfs


def delete_profile(container: str, profile_name: str, mnt: str) -> None:
    """Delete a profile. Prevents deletion of default or active profiles."""
    path = _profile_path(mnt, container, profile_name)
    if not os.path.isdir(path):
        error("NOT_FOUND", f"profile not found: {container}/{profile_name}")

    meta = _read_meta(path)

    # Check if this is the default profile
    if meta.get("default") == "true":
        error("PROFILE_DEFAULT", f"cannot delete default profile: {container}/{profile_name}",
              "use 'sd default profile' to change the default first")

    # Check if this is the active profile
    if meta.get("active") == "true":
        error("PROFILE_ACTIVE", f"cannot delete active profile: {container}/{profile_name}",
              "stop the container using this profile first")

    # Check if it's the last profile for this container
    svc_dir = os.path.dirname(path)
    remaining = [d for d in os.listdir(svc_dir)
                 if os.path.isdir(os.path.join(svc_dir, d)) and d != profile_name]
    if not remaining:
        error("PROFILE_LAST", f"cannot delete the last profile for {container}",
              "at least one profile must exist per container")

    # Delete it
    subprocess.run(btrfs("subvolume", "delete", path), check=True, capture_output=True)
    emit("action", "deleted", f"{container}/{profile_name}")
