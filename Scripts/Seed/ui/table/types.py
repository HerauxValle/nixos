"""
core/table/types.py — flat, tree, grouped, kv, status, split
Rendering resolved centrally via styles.py — callers emit plain rows.
Optional per-call renderers= overrides for special cases.
"""
import io, sys
from lib.variables.colors import c, BOLD, DEFAULT_INDEX, DEFAULT_DIM, BBLACK, BWHITE
from lib.variables.general import TABLE_SECTION_KEY
from ui.table.primitives import _data_rows, _calc_widths, _trunc, _vis, _pad, _term_width
from ui.table.borders    import _hsep, _full_sep, _row_str, _header_cells, _inner_w
from ui.table.styles     import resolve


# ── cell rendering ────────────────────────────────────────────────────────────

def _cell(col, val, row, renderers, width):
    """Render one cell → list[str] (multi-line supported)."""
    override = renderers.get(col) if renderers else None
    raw = resolve(col, str(val), row, override)
    if isinstance(raw, list):
        return [_trunc(str(l), width) for l in raw]
    return [_trunc(str(raw), width)]


def _print_row(cols, row, renderers, widths, idx_w, idx_val, file):
    """Print one logical row, expanding height for multi-line cells."""
    per_col = {col: _cell(col, row.get(col, ""), row, renderers, widths[col]) for col in cols}
    height  = max(len(v) for v in per_col.values())
    wl      = [widths[col] for col in cols]
    for i in range(height):
        idx  = (c(DEFAULT_INDEX, idx_val) if i == 0 else c(DEFAULT_INDEX, "")) if idx_w else ""
        cells = ([idx] if idx_w else []) + \
                [per_col[col][i] if i < len(per_col[col]) else "" for col in cols]
        cw    = ([idx_w] if idx_w else []) + wl
        print(_row_str(cells, cw), file=file)


def _section(cols, widths, idx_w, label, file):
    label_t = _trunc(str(label), widths[cols[0]])
    cells   = ([c(BBLACK, "▸")] if idx_w else []) + \
              [c(BOLD+BWHITE, label_t)] + [""] * (len(cols) - 1)
    cw      = ([idx_w] if idx_w else []) + [widths[col] for col in cols]
    print(_row_str(cells, cw), file=file)


# ── flat ──────────────────────────────────────────────────────────────────────

def _flat(rows, renderers, file, term_w):
    data = _data_rows(rows)
    if not data: return
    cols   = [k for k in data[0] if k != TABLE_SECTION_KEY]
    widths = _calc_widths(cols, rows, True, term_w)
    idx_w  = len(str(len(data) - 1)) + 1
    wl     = [widths[col] for col in cols]
    top    = _hsep(wl, "╭", "┬", "╮", idx_w)
    hsep   = _hsep(wl, "├", "┼", "┤", idx_w)
    bot    = _hsep(wl, "╰", "┴", "╯", idx_w)
    hc, hw = _header_cells(cols, widths, idx_w)
    print(top, file=file); print(_row_str(hc, hw), file=file); print(hsep, file=file)
    prev_sec = False; first = True; n = 0
    for row in rows:
        if TABLE_SECTION_KEY in row:
            if not first: print(hsep, file=file)
            if row[TABLE_SECTION_KEY]:
                _section(cols, widths, idx_w, row[TABLE_SECTION_KEY], file)
                print(hsep, file=file)
            prev_sec = True; continue
        if not first and not prev_sec: print(hsep, file=file)
        prev_sec = False; first = False
        _print_row(cols, row, renderers, widths, idx_w, str(n), file); n += 1
    print(bot, file=file)


# ── tree ──────────────────────────────────────────────────────────────────────

def _flatten(rows, tree_col, depth=0, prefix=""):
    result = []
    data   = [r for r in rows if TABLE_SECTION_KEY not in r]
    for i, row in enumerate(data):
        last   = i == len(data) - 1
        branch = (prefix + ("└─ " if last else "├─ ")) if depth > 0 else ""
        cpfx   = (prefix + ("   " if last else "│  ")) if depth > 0 else ""
        flat   = {k: v for k, v in row.items() if k != "children"}
        flat[tree_col]  = c(BBLACK, branch) + str(flat.get(tree_col, ""))
        flat["_depth"]  = depth
        flat["_section"]= None
        result.append(flat)
        if row.get("children"):
            result += _flatten(row["children"], tree_col, depth + 1, cpfx)
    return result


def _tree(rows, renderers, tree_col, file, term_w):
    flat = []; pending = None
    for src in rows:
        if TABLE_SECTION_KEY in src:
            pending = src[TABLE_SECTION_KEY]; continue
        sub = _flatten([src], tree_col)
        if sub: sub[0]["_section"] = pending; pending = None
        flat += sub
    if not flat: return
    cols   = [k for k in flat[0] if k not in ("_depth", "_section", TABLE_SECTION_KEY)]
    widths = _calc_widths(cols, flat, True, term_w)
    idx_w  = len(str(sum(1 for r in flat if r["_depth"] == 0) - 1)) + 1
    wl     = [widths[col] for col in cols]
    top    = _hsep(wl, "╭", "┬", "╮", idx_w)
    hsep   = _hsep(wl, "├", "┼", "┤", idx_w)
    bot    = _hsep(wl, "╰", "┴", "╯", idx_w)
    hc, hw = _header_cells(cols, widths, idx_w)
    print(top, file=file); print(_row_str(hc, hw), file=file); print(hsep, file=file)
    n = 0; first_root = True
    for row in flat:
        is_root = row["_depth"] == 0
        if is_root:
            if not first_root: print(hsep, file=file)
            if row["_section"] is not None:
                _section(cols, widths, idx_w, row["_section"], file)
                print(hsep, file=file)
            first_root = False
            idx_val = str(n); n += 1
        else:
            idx_val = ""
        _print_row(cols, row, renderers, widths, idx_w, idx_val, file)
    print(bot, file=file)


# ── grouped ───────────────────────────────────────────────────────────────────

def _grouped(rows, renderers, by, file, term_w):
    data    = _data_rows(rows)
    if not data: return
    by_list = by if isinstance(by, list) else [by]
    cols    = [k for k in data[0] if k not in (TABLE_SECTION_KEY, *by_list)]
    widths  = _calc_widths(cols, data, True, term_w)
    idx_w   = len(str(len(data) - 1)) + 1
    wl      = [widths[col] for col in cols]
    top     = _hsep(wl, "╭", "┬", "╮", idx_w)
    hsep    = _hsep(wl, "├", "┼", "┤", idx_w)
    bot     = _hsep(wl, "╰", "┴", "╯", idx_w)
    hc, hw  = _header_cells(cols, widths, idx_w)
    print(top, file=file); print(_row_str(hc, hw), file=file); print(hsep, file=file)
    seen = {}; first = True
    for i, row in enumerate(data):
        gvals = tuple(row.get(b, "") for b in by_list)
        for level, (b, gv) in enumerate(zip(by_list, gvals)):
            if seen.get(level) != gv:
                if not first: print(hsep, file=file)
                indent = "  " * level
                cells_s = ([c(BBLACK, "▸")] if idx_w else []) + \
                           [c(BOLD+BWHITE, _trunc(indent + str(gv), widths[cols[0]]))] + \
                           [""] * (len(cols) - 1)
                print(_row_str(cells_s, ([idx_w] if idx_w else []) + wl), file=file)
                print(hsep, file=file)
                for d in range(level + 1, len(by_list)): seen.pop(d, None)
                seen[level] = gv
        first = False
        _print_row(cols, row, renderers, widths, idx_w, str(i), file)
        if i < len(data)-1 and data[i+1].get(by_list[0],"") == gvals[0]:
            print(hsep, file=file)
    print(bot, file=file)


# ── kv ────────────────────────────────────────────────────────────────────────

def _kv(rows, renderers, file, term_w):
    if not rows: return
    key_w  = max(len(str(r.get("key", ""))) for r in _data_rows(rows) or [{"key":""}])
    val_w  = max(4, term_w - key_w - 7)
    widths = {"key": key_w, "value": val_w}
    wl     = [key_w, val_w]
    top    = _hsep(wl, "╭", "┬", "╮")
    hsep   = _hsep(wl, "├", "┼", "┤")
    bot    = _hsep(wl, "╰", "┴", "╯")
    print(top, file=file)
    first = True
    for row in rows:
        if TABLE_SECTION_KEY in row:
            label = row[TABLE_SECTION_KEY]
            if label:
                if not first: print(hsep, file=file)
                _section(["key","value"], widths, 0, label, file)
                print(hsep, file=file)
            continue
        if not first: print(hsep, file=file)
        first = False
        _print_row(["key","value"], row, renderers, widths, 0, "", file)
    print(bot, file=file)


# ── status ────────────────────────────────────────────────────────────────────

def _status(rows, renderers, indicator_col, file, term_w):
    data = _data_rows(rows)
    if not data: return
    cols = [k for k in data[0] if k not in (indicator_col, TABLE_SECTION_KEY)]
    # pre-render indicator values to get accurate visual width
    ind_rendered = [
        resolve(indicator_col, str(r.get(indicator_col, "")), r,
                renderers.get(indicator_col) if renderers else None)
        for r in data
    ]
    ind_w  = max(_vis(indicator_col),
                 max((_vis(v) for v in ind_rendered), default=0)) + 1
    idx_w  = len(str(len(data) - 1)) + 1
    widths = _calc_widths(cols, data, False, term_w - ind_w - idx_w - 6)
    wl     = [idx_w, ind_w] + [widths[col] for col in cols]
    top    = _hsep(wl, "╭", "┬", "╮")
    hsep   = _hsep(wl, "├", "┼", "┤")
    bot    = _hsep(wl, "╰", "┴", "╯")
    hc     = [c(BOLD+BWHITE, "#"), c(BOLD+BWHITE, "")] + \
             [c(BOLD+BWHITE, _trunc(col, widths[col])) for col in cols]
    print(top, file=file); print(_row_str(hc, wl), file=file); print(hsep, file=file)
    prev_sec = False; first = True; data_idx = 0
    for row in rows:
        if TABLE_SECTION_KEY in row:
            if not first: print(hsep, file=file)
            if row[TABLE_SECTION_KEY]:
                cells_s = [c(BBLACK, "▸"), ""] + \
                          [c(BOLD+BWHITE, _trunc(str(row[TABLE_SECTION_KEY]), widths[cols[0]])) if j==0 else ""
                           for j, col in enumerate(cols)]
                print(_row_str(cells_s, wl), file=file); print(hsep, file=file)
            prev_sec = True; continue
        if not first and not prev_sec: print(hsep, file=file)
        prev_sec = False; first = False
        idx_str = c(DEFAULT_INDEX, str(data_idx))
        ind_raw = ind_rendered[data_idx]; data_idx += 1
        per_col = {col: _cell(col, row.get(col,""), row, renderers, widths[col]) for col in cols}
        height  = max(len(v) for v in per_col.values())
        for i in range(height):
            idx_cell = (idx_str if i == 0 else c(DEFAULT_INDEX, ""))
            ind_cell = (_trunc(ind_raw, ind_w) if i == 0 else "")
            cells    = [idx_cell, ind_cell] + [per_col[col][i] if i < len(per_col[col]) else "" for col in cols]
            print(_row_str(cells, wl), file=file)
    print(bot, file=file)


# ── split ─────────────────────────────────────────────────────────────────────

def _split(left_rows, right_rows, left_rnd, right_rnd, file, term_w):
    half = (term_w - 2) // 2
    def _render(rows, rnd, w):
        buf = io.StringIO(); _flat(rows, rnd, buf, w); return buf.getvalue().splitlines()
    ll = _render(left_rows, left_rnd, half)
    rl = _render(right_rows, right_rnd, half)
    h  = max(len(ll), len(rl))
    ll += [""] * (h - len(ll)); rl += [""] * (h - len(rl))
    for l, r in zip(ll, rl):
        print(l + " " * max(0, half - _vis(l)) + "  " + r, file=file)


# ── public API ────────────────────────────────────────────────────────────────

def table(
    rows:            list[dict],
    renderers:       dict = None,  # {col: lambda v, row -> str | list[str]} — overrides registry
    type:            str  = "flat",
    file                  = sys.stdout,
    tree_col:        str  = None,
    by               = None,
    indicator_col:   str  = None,
    right_rows:      list = None,
    right_renderers: dict = None,
) -> None:
    if not rows: return
    rnd    = renderers or {}
    term_w = _term_width()
    if type == "flat":
        _flat(rows, rnd, file, term_w)
    elif type == "tree":
        col = tree_col or list(_data_rows(rows)[0].keys())[0]
        _tree(rows, rnd, col, file, term_w)
    elif type == "grouped":
        _grouped(rows, rnd, by or "", file, term_w)
    elif type == "kv":
        _kv(rows, rnd, file, term_w)
    elif type == "status":
        _status(rows, rnd, indicator_col or "", file, term_w)
    elif type == "split":
        _split(rows, right_rows or [], rnd, right_renderers or {}, file, term_w)
    else:
        _flat(rows, rnd, file, term_w)