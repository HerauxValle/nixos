"""
core/blueprint/validate.py — user-facing blueprint validation
"""
from common.emit import emit

import os
from lib.variables.colors import c, BRED, YELLOW


def validate(name: str) -> None:
    from common.session import get_active
    from common.errors  import error
    from parser.processing.blueprint import loads

    mnt    = get_active()
    bp_dir = os.path.join(mnt, "blueprints")
    match  = [f for f in os.listdir(bp_dir) if os.path.splitext(f)[0] == name]
    if not match:
        error("NOT_FOUND", "blueprint not found", name)

    with open(os.path.join(bp_dir, match[0]), "r", encoding="utf-8") as f:
        text = f.read()

    bp = loads(text)

    if bp.errors:
        emit("table", [{"error": e} for e in bp.errors], type="flat")

    if bp.warnings:
        emit("table", [{"warning": w} for w in bp.warnings], type="flat")

    if bp.errors:
        emit("action", "result", f"invalid — {len(bp.errors)} error(s)")
    else:
        emit("action", "result", "valid" if not bp.warnings
            else f"valid — {len(bp.warnings)} warning(s)")