"""
common/ir.py — IR normalization, validation, transforms
All pure functions — no I/O, no state.
"""
import sys
from typing import Any

import sys
from typing import Any


# ── allowed meta keys per type ────────────────────────────────────────────────
_META_KEYS = {
    "table":   {"view", "tree_col", "by", "indicator_col",
                "right_rows", "right_renderers", "renderers"},
    "action":  set(),
    "error":   set(),
    "warning": set(),
    "log":     set(),
}


# ── normalize ─────────────────────────────────────────────────────────────────

# ── semantic event → IR type mapping ─────────────────────────────────────────
# e.g. "container.run" → "action", "process.list" → "table"
_EVENT_MAP: dict[str, str] = {}  # extend via register_event()


def register_event(event: str, ir_type: str) -> None:
    """Register a semantic event name → IR type. Issue 15/19."""
    _EVENT_MAP[event] = ir_type


def _normalize(type_: str, args: tuple, kwargs: dict) -> dict:
    """Convert any emit() call signature into canonical IR."""
    # resolve semantic event name if registered
    if "." in type_ and type_ in _EVENT_MAP:
        type_ = _EVENT_MAP[type_]
    elif "." in type_:
        # unknown semantic event → treat as action with event name as key
        kwargs.setdefault("rows", [{"key": type_, "value": str(args[0]) if args else ""}])
        type_ = "action"
    rows = kwargs.pop("rows", None)
    meta = kwargs.pop("meta", {}) or {}

    # absorb remaining kwargs into meta (e.g. type="tree", indicator_col="status")
    allowed = _META_KEYS.get(type_, set())
    for k in list(kwargs):
        if k in allowed or type_ == "table":
            v = kwargs.pop(k)
            # rename type= to view= to avoid collision with IR top-level type
            meta["view" if k == "type" else k] = v

    if rows is not None:
        return {"type": type_, "rows": rows, "meta": meta, "v": 1}

    # positional sugar → rows
    if type_ == "action":
        key     = args[0] if len(args) > 0 else ""
        value   = args[1] if len(args) > 1 else ""
        comment = args[2] if len(args) > 2 else ""
        row = {"key": str(key), "value": str(value)}
        if comment: row["comment"] = str(comment)
        return {"type": "action", "v": 1, "rows": [row], "meta": meta}

    elif type_ == "error":
        code    = args[0] if len(args) > 0 else ""
        msg     = args[1] if len(args) > 1 else ""
        details = args[2:] if len(args) > 2 else ()
        r = [{"code": str(code), "message": str(msg),
               "detail": str(details[0]) if details else ""}]
        for d in details[1:]:
            r.append({"code": "", "message": "", "detail": str(d)})
        return {"type": "error", "v": 1, "rows": r, "meta": meta}

    elif type_ == "warning":
        msg    = args[0] if len(args) > 0 else ""
        detail = args[1] if len(args) > 1 else ""
        return {"type": "warning", "v": 1,
                "rows": [{"key": "warning", "value": str(msg), "comment": str(detail)}],
                "meta": meta}

    elif type_ == "log":
        msg = args[0] if args else ""
        return {"type": "log", "v": 1,
                "rows": [{"message": str(msg)}],
                "meta": meta}

    elif type_ == "table":
        rows = args[0] if args else []
        # normalize type= kwarg to view= to avoid meta["type"] collision
        if "type" in meta:
            meta["view"] = meta.pop("type")
        return {"type": "table", "v": 1, "rows": rows, "meta": meta}

    elif type_ == "section":
        label    = args[0] if args else ""
        children = kwargs.pop("children", [])
        return {"type": "section", "v": 1,
                "rows": [{"__section__": str(label)}],
                "meta": meta,
                "children": children}

    # fallback — treat as action
    key   = args[0] if args else type_
    value = args[1] if len(args) > 1 else ""
    return {"type": "action",
            "rows": [{"key": str(key), "value": str(value)}],
            "meta": meta}


# ── union schema fix ──────────────────────────────────────────────────────────

# ── per-type required fields ──────────────────────────────────────────────────
_REQUIRED_FIELDS: dict[str, set] = {
    "action":  {"key", "value"},
    "error":   {"code", "message"},
    "warning": {"key", "value"},
    "log":     {"message"},
    "table":   set(),   # rows are free-form
    "section": set(),
}


def _validate(ir: dict) -> None:
    """Fail fast on malformed IR — shape + per-type field contracts."""
    assert "type" in ir,             "IR missing 'type'"
    assert "rows" in ir,             "IR missing 'rows'"
    assert isinstance(ir["rows"], list), "'rows' must be a list"
    required = _REQUIRED_FIELDS.get(ir["type"], set())
    if required:
        data = [r for r in ir["rows"] if "__section__" not in r and "_meta" not in r]
        for row in data:
            missing = required - row.keys()
            assert not missing, f"IR type '{ir["type"]}' row missing fields: {missing}"


def _apply_meta(ir: dict) -> dict:
    """Apply meta transforms: columns filter, sort, column_types override."""
    rows = ir["rows"]
    meta = ir.get("meta", {})

    # issue 24: column filter
    cols = meta.pop("columns", None)
    if cols:
        rows = [{k: r.get(k, "") for k in cols} for r in rows]

    # issue 24: sort
    sort_key = meta.pop("sort", None)
    if sort_key and rows:
        try:
            rows = sorted(rows, key=lambda r: str(r.get(sort_key, "")))
        except Exception:
            pass

    # issue 32: explicit column order — store in meta for renderers
    col_order = meta.pop("col_order", None)
    if col_order:
        meta["_col_order"] = col_order
        rows = [{k: r.get(k, "") for k in col_order if k in r} for r in rows]

    # issue 18: per-call column_types override — pass through to renderer
    # (already in meta, renderers check meta.get("column_types"))

    # issue 25: pagination — truncate + append summary row
    max_r = int(meta.pop("max_rows", 0))
    if max_r and len(rows) > max_r:
        hidden = len(rows) - max_r
        rows   = rows[:max_r]
        rows.append({"__section__": f"... {hidden} more row(s) not shown"})

    ir["rows"] = rows
    return ir


def _fill_keys(rows: list[dict]) -> list[dict]:
    """Ensure all data rows have the same keys (union). Skips section/meta rows."""
    if not rows: return rows
    data_rows = [r for r in rows if "__section__" not in r and "_meta" not in r]
    if not data_rows: return rows
    all_keys = sorted(set().union(*(r.keys() for r in data_rows)))
    return [
        r if ("__section__" in r or "_meta" in r)
        else {k: r.get(k, "") for k in all_keys}
        for r in rows
    ]


def clean_rows(rows: list[dict]) -> list[dict]:
    """Strip internal/section/meta rows and internal keys for external output."""
    return [
        {k: v for k, v in r.items() if not k.startswith("_")}
        for r in rows
        if "__section__" not in r and "_meta" not in r
    ]


def to_public(ir: dict) -> dict:
    """Transform internal IR → public JSON. Strips internal fields, adds schema."""
    return {
        "schema_version": ir.get("v", 1),
        "type":           ir["type"],
        "rows":           clean_rows(ir["rows"]),
        **({"meta": pub_meta}
           if (pub_meta := {k: v for k, v in ir.get("meta", {}).items()
                           if not k.startswith("_") and k not in ("view", "stream", "priority", "_col_order")}) else {}),
    }