"""
orchestration/profile/list.py — list profiles
"""

from common.emit import emit
from ui.table import table
import os
from orchestration.profile.create import _read_meta


def list_profiles(mnt: str) -> None:
    """List all profiles grouped by service."""
    pdir = os.path.join(mnt, "profiles")
    if not os.path.isdir(pdir):
        emit("action", "profiles", "none")
        return

    rows = []
    for svc in sorted(os.listdir(pdir)):
        svc_dir = os.path.join(pdir, svc)
        if not os.path.isdir(svc_dir):
            continue
        for name in sorted(os.listdir(svc_dir)):
            profile_dir = os.path.join(svc_dir, name)
            if not os.path.isdir(profile_dir):
                continue
            meta = _read_meta(profile_dir)
            default = "✓" if meta.get("default") == "true" else ""
            active = "✓" if meta.get("active") == "true" else ""
            rows.append({
                "service": svc,
                "profile": name,
                "default": default,
                "active": active,
            })

    if not rows:
        emit("action", "profiles", "none")
        return

    table(rows, type="grouped", by="service")
