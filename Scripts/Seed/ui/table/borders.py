"""
core/table/borders.py — border/separator builders and row string
"""
from lib.variables.colors import c, BOLD, DEFAULT_LABEL, BBLACK
from ui.table.primitives import _pad, _trunc

def _hsep(w_list, left, mid, right, idx_w=0, fill="─"):
    parts = ([fill*(idx_w+2)] if idx_w else []) + [fill*(w+2) for w in w_list]
    return c(BBLACK, left + mid.join(parts) + right)

def _inner_w(w_list, idx_w):
    total = sum(w+2 for w in w_list) + len(w_list) - 1
    if idx_w: total += idx_w + 3
    return total

def _full_sep(w_list, left, right, idx_w=0):
    return c(BBLACK, left + "─" * _inner_w(w_list, idx_w) + right)

def _row_str(cells, widths):
    div = c(BBLACK, "│")
    return div + div.join(f" {_pad(cell, w)} " for cell, w in zip(cells, widths)) + div

def _header_cells(cols, widths, idx_w):
    cells, ws = [], []
    if idx_w: cells.append(c(BOLD+DEFAULT_LABEL, "#")); ws.append(idx_w)
    for col in cols:
        cells.append(c(BOLD+DEFAULT_LABEL, _trunc(col, widths[col]))); ws.append(widths[col])
    return cells, ws
