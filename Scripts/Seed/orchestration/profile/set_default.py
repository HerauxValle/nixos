"""
orchestration/profile/set_default.py — set a profile as default
"""

from common.emit import emit
from common.errors import error
import os
from orchestration.profile.create import _profile_path, _read_meta, _write_meta


def set_default(container: str, profile_name: str, mnt: str) -> None:
    """Set a profile as the default for a container."""
    path = _profile_path(mnt, container, profile_name)
    if not os.path.isdir(path):
        error("NOT_FOUND", f"profile not found: {container}/{profile_name}")

    # Find all profiles for this container
    svc_dir = os.path.dirname(path)
    for name in os.listdir(svc_dir):
        profile_dir = os.path.join(svc_dir, name)
        if not os.path.isdir(profile_dir):
            continue
        meta = _read_meta(profile_dir)
        # Unset default on all profiles
        if meta.get("default") == "true":
            meta["default"] = "false"
            _write_meta(profile_dir, meta)

    # Set this profile as default
    meta = _read_meta(path)
    meta["default"] = "true"
    _write_meta(path, meta)

    emit("action", "set", f"{container}/{profile_name} as default")
