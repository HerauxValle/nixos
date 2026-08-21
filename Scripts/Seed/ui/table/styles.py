"""
core/table/styles.py — universal cell type registry + theming
Maps column names → semantic type, types → render functions.
Active theme selected via set_theme(). Default: "dark".
"""
from lib.variables.colors import (
    c, BOLD, BBLACK, CYAN, GREEN, YELLOW,
    DEFAULT, DEFAULT_CMD, DEFAULT_FLAG, DEFAULT_DIM,
    DEFAULT_INDEX, DEFAULT_LABEL, DEFAULT_SUCCESS, DEFAULT_WARN,
    BRED, BWHITE, ORANGE, WHITE,
)

# ── theme definitions ─────────────────────────────────────────────────────────

THEMES: dict[str, dict[str, callable]] = {
    "dark": {
        "cmd":      lambda v: c(DEFAULT_CMD,     v),
        "flag":     lambda v: c(DEFAULT_FLAG,    v),
        "dim":      lambda v: c(BBLACK,          v),
        "muted":    lambda v: c(DEFAULT_DIM,     v),
        "accent":   lambda v: c(CYAN,            v),
        "success":  lambda v: c(DEFAULT_SUCCESS, v),
        "warn":     lambda v: c(DEFAULT_WARN,    v),
        "error":    lambda v: c(BRED,            v),
        "index":    lambda v: c(DEFAULT_INDEX,   v),
        "header":   lambda v: c(BOLD+DEFAULT_LABEL, v),
        "section":  lambda v: c(BOLD+CYAN,       v),
        "comment":  lambda v: c(BBLACK,          v),
        "default":  lambda v: c(DEFAULT,         v),
        "value":    lambda v: c(DEFAULT_SUCCESS, v),
        "status":   lambda v: (
            c(GREEN,       f"● {v}") if v in ("running", "valid", "ok", "healthy")
            else c(BRED,   f"○ {v}") if v in ("exited", "dead", "error", "missing")
            else c(YELLOW, f"◐ {v}") if v in ("starting", "stopping", "warn", "unknown")
            else c(BBLACK, f"  {v}")
        ),
    },
    "minimal": {
        "cmd":      lambda v: v,
        "flag":     lambda v: v,
        "dim":      lambda v: v,
        "muted":    lambda v: v,
        "accent":   lambda v: v,
        "success":  lambda v: v,
        "warn":     lambda v: f"! {v}",
        "error":    lambda v: f"ERR {v}",
        "index":    lambda v: v,
        "header":   lambda v: v.upper(),
        "section":  lambda v: f"=== {v} ===",
        "comment":  lambda v: v,
        "default":  lambda v: v,
        "value":    lambda v: v,
        "status":   lambda v: (
            f"[+] {v}" if v in ("running", "valid", "ok", "healthy")
            else f"[-] {v}" if v in ("exited", "dead", "error", "missing")
            else f"[~] {v}"
        ),
    },
}

_active_theme: str = "dark"


def set_theme(name: str) -> None:
    global _active_theme
    if name not in THEMES:
        raise ValueError(f"unknown theme '{name}' — available: {', '.join(THEMES)}")
    _active_theme = name


def get_theme() -> str:
    return _active_theme


def register_theme(name: str, styles: dict) -> None:
    """Register a custom theme. Issue 33/40."""
    THEMES[name] = styles


# ── column name → semantic type ───────────────────────────────────────────────

COLUMN_TYPES: dict[str, str] = {
    "command": "cmd",   "flag": "flag",     "flags": "flag",
    "usage":   "muted", "info": "dim",      "description": "dim",
    "targets": "muted",
    "name":    "cmd",   "service": "accent","status": "status",
    "pid":     "dim",   "kind": "accent",   "layer": "dim",
    "created": "dim",   "alive": "status",
    "mounted": "dim",   "active": "success","source": "success",
    "size":    "dim",   "hash": "dim",
    "rule":    "cmd",   "key": "cmd",       "value": "value",
    "shebang": "accent","file": "default",
    "doc":     "cmd",   "path": "dim",
    "line":    "dim",   "error": "error",   "warning": "warn",
    "result":  "value",
    "process": "cmd",   "action": "cmd",    "detail": "dim",
    "message": "warn",  "code": "error",
    "profile": "default","type": "accent",  "refs": "value",
    "rootfs":  "dim",   "id": "dim",
    "comment": "comment",
}


def resolve(col: str, val: str, row: dict, override: callable = None,
            column_types: dict = None) -> str:
    """
    Resolve a cell value to a styled string.
    override   — per-call renderer fn, wins over all
    column_types — per-call type overrides (issue 18)
    """
    if override:
        return override(val, row)
    ct         = column_types or {}
    style_name = ct.get(col) or COLUMN_TYPES.get(col, "default")
    theme      = THEMES.get(_active_theme, THEMES["dark"])
    style_fn   = theme.get(style_name, theme["default"])
    return style_fn(val)