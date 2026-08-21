"""
core/img/list.py — list and identify mounted imgs
"""

import os
import tomllib

from common.emit import emit
from ui.table  import table
from lib.variables.colors import c, DEFAULT, DEFAULT_SUCCESS, BBLACK, CYAN
from lib.variables.general import *



def _get_active() -> str | None:
    try:
        from common.session import get_active
        return get_active()
    except Exception:
        return None


def list_images() -> None:
    """List actual image files (not mounted containers)."""
    # Find all .img files recursively from common search paths
    seen_paths = set()
    img_files = []
    search_paths = [
        os.path.expanduser("~"),
        "/mnt",
        "/home",
    ]

    for base_path in search_paths:
        if not os.path.isdir(base_path):
            continue
        try:
            # Search up to 3 levels deep for .img files (avoid full fs scan)
            for root, dirs, files in os.walk(base_path):
                # Limit depth
                depth = root[len(base_path):].count(os.sep)
                if depth > 3:
                    dirs[:] = []  # Don't recurse deeper
                    continue

                for f in files:
                    # Only match files named properly (not just .img)
                    if f.endswith(".img") and f != ".img" and len(f) > 4:
                        full_path = os.path.abspath(os.path.join(root, f))
                        # Skip if already seen (dedup)
                        if full_path in seen_paths:
                            continue
                        seen_paths.add(full_path)

                        try:
                            stat = os.stat(full_path)
                            # Only include files > 1MB (filter noise)
                            if stat.st_size > 1024 * 1024:
                                img_files.append({
                                    "path": full_path,
                                    "name": f,
                                    "size_mb": stat.st_size // (1024 * 1024),
                                })
                        except OSError:
                            pass
        except (OSError, PermissionError):
            pass

    if not img_files:
        emit("action", "images", "none found")
        return

    # Get active mount to mark which image is selected
    active_mnt = _get_active()
    active_img = None
    if active_mnt:
        try:
            with open(f"{active_mnt}/meta.toml", "rb") as f:
                meta = tomllib.load(f)
            active_img = meta.get("img_path", "")
        except Exception:
            pass

    rows = []
    for img in sorted(img_files, key=lambda x: x["path"]):
        active = "✓" if img["path"] == active_img else ""
        rows.append({
            "name": img["name"],
            "path": img["path"],
            "size_mb": img["size_mb"],
            "active": active,
        })

    emit("table", rows)


def which_image() -> None:
    active = _get_active()
    if not active:
        emit("action", "image", "none selected")
        return
    try:
        with open(f"{active}/meta.toml", "rb") as f:
            meta = tomllib.load(f)
        emit("action", "image", meta.get("name", os.path.basename(active)))
    except Exception:
        emit("action", "image", os.path.basename(active))