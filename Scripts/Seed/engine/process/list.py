"""
core/process/list.py — display tracked processes as a tree table
"""

from common.emit import emit

from common.process import list_tracked
from ui.table     import table, TABLE_SECTION_KEY
from lib.variables.colors import c, DEFAULT, DEFAULT_SUCCESS, BRED, BBLACK, DEFAULT_WARN, CYAN


def _alive_str(alive: bool) -> str:
    return c(DEFAULT_SUCCESS, "● running") if alive else c(BRED, "○ dead")


def _kind_str(kind: str) -> str:
    colors = {
        "container": CYAN,
        "layer":     DEFAULT_WARN,
        "pull":      DEFAULT_WARN,
        "process":   DEFAULT,
    }
    col = colors.get(kind, DEFAULT)
    return c(col, kind)


def list_processes() -> None:
    
    procs = list_tracked()

    if not procs:
        emit("action", "processes", "none")
        return

    # build tree: group children under parents
    by_name  = {p["name"]: p for p in procs}
    roots    = [p for p in procs if not p.get("parent")]
    children = {}
    for p in procs:
        par = p.get("parent")
        if par:
            children.setdefault(par, []).append(p)

    rows = []

    def _add(p: dict, depth: int = 0) -> None:
        prefix = "  " * depth
        tree   = (prefix + "├─ " if depth > 0 else "")
        rows.append({
            "process": tree + p["name"],
            "pid":     str(p["pid"]),
            "kind":    _kind_str(p["kind"]),
            "status":  _alive_str(p["alive"]),
        })
        for child in sorted(children.get(p["name"], []), key=lambda x: x["name"]):
            _add(child, depth + 1)

    for root in sorted(roots, key=lambda x: x["name"]):
        _add(root)
        # add separator between root trees if multiple
        if root != roots[-1]:
            rows.append({TABLE_SECTION_KEY: ""})

    emit("table", rows, type="tree", tree_col="process")