"""
core/blueprint/actions.py — add, edit, list, delete blueprints
"""

import os
from orchestration.filemanager import add, edit, list_files, delete
from lib.variables.general import *

FOLDER      = DIR_BLUEPRINTS
DEFAULT_EXT = DEFAULT_BLUEPRINT_EXT


def blueprint_add(name: str, ext: str = DEFAULT_EXT) -> None:
    add(FOLDER, ext if ext.startswith(".") else f".{ext}", name)


def blueprint_edit(name: str, editor: str | None = None) -> None:
    edit(FOLDER, name, editor)


def blueprint_delete(name: str) -> None:
    delete(FOLDER, name)


def blueprint_list() -> None:
    from lib.variables.colors import c, DEFAULT, DEFAULT_SUCCESS, BBLACK
    from common.shebang import read_shebangs
    from common.emit import emit
    from ui.table import table

    def _row(f, path, origin: str):
        name, ext = os.path.splitext(f)
        size      = os.path.getsize(path)
        shebangs  = read_shebangs(path)
        fmt       = shebangs[0] if shebangs else ext.lstrip(".")
        size_str  = f"{size}B" if size < 1024 else f"{size // 1024}KB"
        return {
            "name":   name,
            "ext":    ext,
            "format": fmt,
            "origin": origin,
            "size":   size_str,
            "__colors__": {
                "name":   lambda v: c(DEFAULT, v),
                "ext":    lambda v: c(BBLACK, v),
                "format": lambda v: c(DEFAULT_SUCCESS, v),
                "origin": lambda v: c(DEFAULT_SUCCESS if v == "external" else DEFAULT, v),
                "size":   lambda v: c(BBLACK, v),
            }
        }

    from common.session import get_active
    mnt = get_active()
    rows = []

    # internal blueprints
    internal_dir = os.path.join(mnt, FOLDER)
    if os.path.isdir(internal_dir):
        with os.scandir(internal_dir) as it:
            for entry in sorted(it, key=lambda e: e.name):
                if entry.is_file():
                    rows.append(_row(entry.name, entry.path, "internal"))

    # external blueprints
    try:
        from orchestration.settings import get_external_blueprints_dir
        ext_dir = get_external_blueprints_dir()
        if ext_dir and os.path.isdir(ext_dir):
            with os.scandir(ext_dir) as it:
                for entry in sorted(it, key=lambda e: e.name):
                    if entry.is_file():
                        rows.append(_row(entry.name, entry.path, "external"))
    except Exception as e:
        emit("log", f"external blueprints load failed: {e}")
        pass

    if not rows:
        emit("action", "blueprints", "none")
        return

    rows = [{k: v for k, v in r.items() if k != "__colors__"} for r in rows]
    emit("table", rows, type="flat")