"""
core/filemanager.py — generic file manager for any file type inside an img
"""
from common.emit import emit

import os
import subprocess
import shutil
from lib.variables.general import *




def _get_mnt() -> str:
    from common.session import get_active
    return get_active()


def _find_editor(override: str | None) -> str:
    if override:
        return override
    editor = os.environ.get("EDITOR")
    if editor:
        return editor
    for e in EDITOR_FALLBACKS:
        if shutil.which(e):
            return e
    from common.errors import error
    error("NO_EDITOR", "no editor found", "use -e to specify one")


def _resolve(mnt: str, folder: str, name: str, ext: str | None = None) -> str:
    """
    Resolve full path. If ext given, use it directly.
    If not, find any file in folder whose stem matches name.
    """
    d = os.path.join(mnt, folder)
    if ext:
        n = name if name.endswith(ext) else f"{name}{ext}"
        return os.path.join(d, n)
    # find by stem
    matches = [f for f in os.listdir(d) if os.path.splitext(f)[0] == name]
    if matches:
        return os.path.join(d, matches[0])
    return os.path.join(d, name)


def add(folder: str, ext: str, name: str) -> None:
    from common.errors import error
    mnt  = _get_mnt()
    path = _resolve(mnt, folder, name, ext)
    if os.path.exists(path):
        error("ALREADY_EXISTS", f"{folder} already exists", name)
    open(path, "w").close()
    emit("log", f"created → {path}")
    emit("action", "created", os.path.basename(path))


def edit(folder: str, name: str, editor_override: str | None = None, ext: str | None = None) -> None:
    from common.errors import error
    mnt  = _get_mnt()
    path = _resolve(mnt, folder, name, ext)
    if not os.path.exists(path):
        error("NOT_FOUND", f"{folder} not found", name)
    editor = _find_editor(editor_override)
    emit("log", f"opening {path} with {editor}...")
    subprocess.call([editor, path])
    emit("action", "saved", os.path.basename(path))


def delete(folder: str, name: str, ext: str | None = None) -> None:
    from common.errors import error
    mnt  = _get_mnt()
    path = _resolve(mnt, folder, name, ext)
    if not os.path.exists(path):
        error("NOT_FOUND", f"{folder} not found", name)
    os.remove(path)
    emit("log", f"deleted → {path}")
    emit("action", "deleted", os.path.basename(path))


def list_files(folder: str, ext: str | None = None, row_fn=None) -> None:
    """
    List files in folder. If ext given, filter by it.
    row_fn(filename) -> dict for custom row building, else default name+size.
    """
    from ui.table  import table
    mnt   = _get_mnt()
    d     = os.path.join(mnt, folder)
    files = sorted(f for f in os.listdir(d) if not ext or f.endswith(ext))

    if not files:
        emit("action", folder, "none found")
        return

    if row_fn:
        rows = [row_fn(f, os.path.join(d, f)) for f in files]
        rows = [{k: v for k, v in r.items() if k != "__colors__"} for r in rows]
    else:
        rows = []
        for f in files:
            size = os.path.getsize(os.path.join(d, f))
            rows.append({
                "name": f,
                "size": f"{size}B" if size < 1024 else f"{size//1024}KB",
            })

    table(rows)