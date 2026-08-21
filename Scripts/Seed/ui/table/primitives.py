"""
core/table/primitives.py — string helpers, width calc, terminal width
"""
import re, os, functools
from lib.variables.general import TABLE_SECTION_KEY

_term_w_cache: int | None = None


def _strip_ansi(s: str) -> str:
    return re.sub(r"\033\[[0-9;]*m", "", s)

def _vis(s: str) -> int:
    return len(_strip_ansi(s))

def _pad(s: str, w: int) -> str:
    return s + " " * max(0, w - _vis(s))

def _trunc(s: str, w: int) -> str:
    """Truncate to visual width w, preserving ANSI codes."""
    if _vis(s) <= w:
        return s
    # walk chars accumulating visual width
    result = []; vis = 0; i = 0; ansi_buf = []
    target = max(0, w - 3)
    while i < len(s):
        if s[i] == "\033":
            # collect full escape sequence
            j = i
            while j < len(s) and s[j] != "m":
                j += 1
            seq = s[i:j+1]
            result.append(seq)
            i = j + 1
        else:
            if vis >= target:
                break
            result.append(s[i]); vis += 1; i += 1
    return "".join(result) + ("..." if _vis(s) > w else "")

def _data_rows(rows: list) -> list:
    return [r for r in rows if TABLE_SECTION_KEY not in r]

def invalidate_term_width() -> None:
    global _term_w_cache
    _term_w_cache = None


def _term_width() -> int:
    global _term_w_cache
    if _term_w_cache is not None:
        return _term_w_cache
    try:
        from orchestration.settings import get_rule
        rule = get_rule("TABLE_SIZE") or "auto"
        if rule == "max":
            try: _term_w_cache = os.get_terminal_size().columns; return _term_w_cache
            except OSError: _term_w_cache = 220; return _term_w_cache
    except Exception:
        pass
    try:
        _term_w_cache = os.get_terminal_size().columns
    except OSError:
        _term_w_cache = 120
    return _term_w_cache

def _calc_widths(cols: list, rows: list, has_index: bool, term_w: int,
                 rendered: dict = None) -> dict:
    """
    Calculate column widths fitting term_w.
    rendered: optional {col: [str]} of pre-rendered values for accurate vis-width.
    """
    data = _data_rows(rows)
    widths = {col: _vis(col) for col in cols}

    for row in data:
        for col in cols:
            if rendered and col in rendered:
                # use max vis width of rendered values for this col
                pass  # handled below
            else:
                widths[col] = max(widths[col], _vis(str(row.get(col, ""))))

    if rendered:
        for col, vals in rendered.items():
            if col in widths:
                widths[col] = max(widths[col], max((_vis(v) for v in vals), default=0))

    # section label may widen first col
    if cols:
        for row in rows:
            if TABLE_SECTION_KEY in row and row[TABLE_SECTION_KEY]:
                widths[cols[0]] = max(widths[cols[0]], _vis(str(row[TABLE_SECTION_KEY])))

    idx_w    = (_vis(str(max(len(data) - 1, 0))) + 1) if has_index else 0
    overhead = (idx_w + 3 if has_index else 0) + len(cols) * 3 + 1
    avail    = max(1, term_w - overhead)
    total    = sum(widths.values())

    if total > avail:
        for col in cols:
            widths[col] = max(4, int(avail * widths[col] / total))

    # distribute remaining space largest-first
    used = sum(widths.values()); rem = avail - used
    for col in sorted(cols, key=lambda k: widths[k], reverse=True):
        if rem <= 0: break
        widths[col] += 1; rem -= 1

    return widths