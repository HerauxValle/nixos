"""
core/db/actions.py — doc database
"""
from common.emit import emit
import os
from lib.variables.general import *

def _sources() -> list[tuple[str, str]]:
    found = {}
    if os.path.isdir(PROJECT_HELP):
        for f in os.listdir(PROJECT_HELP):
            if f.endswith(".md"):
                found[os.path.splitext(f)[0].lower()] = os.path.join(PROJECT_HELP, f)
    try:
        from common.session import get_active
        img_help = os.path.join(get_active(), "help")
        if os.path.isdir(img_help):
            for f in os.listdir(img_help):
                if f.endswith(".md"):
                    found[os.path.splitext(f)[0].lower()] = os.path.join(img_help, f)
    except Exception:
        pass
    return sorted(found.items())

def db_list() -> None:
    from ui.table import table
    from lib.variables.colors import c, DEFAULT, BBLACK, DEFAULT_SUCCESS
    sources = _sources()
    if not sources:
        emit("action", "db", "no docs found"); return
    rows = []
    for name, path in sources:
        size = os.path.getsize(path)
        src  = "img" if "simpleDocker" in path else "project"
        rows.append({"name": name, "source": src,
                     "size": f"{size}B" if size < 1024 else f"{size//1024}KB"})
    table(rows)

def db_show(name: str) -> None:
    from common.errors import error
    from ui.md.renderer import render_file
    sources = dict(_sources())
    key = name.lower().rstrip(".md")
    if key not in sources:
        error("NOT_FOUND", f"doc not found: {name}", "run 'sd list db' to see available docs")
    render_file(sources[key])