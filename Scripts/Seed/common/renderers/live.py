"""
common/renderers/live.py — LiveTable streaming renderer
Uses styles.py registry — no per-instance color dicts.
"""
import sys
from lib.variables.colors import c, BOLD, DEFAULT_LABEL, DEFAULT_INDEX
from ui.table.primitives import _trunc, _term_width, _vis
from ui.table.borders    import _hsep, _row_str
from ui.table.styles     import resolve


class LiveTable:
    def __init__(self, cols: dict, index: bool = True, file=sys.stdout):
        """
        cols: {col_name: natural_width} — widths are hints, adjusted to terminal.
        """
        term_w   = _term_width()
        idx_w    = 4 if index else 0
        overhead = (idx_w + 3 if index else 0) + len(cols) * 3 + 1
        avail    = term_w - overhead
        total    = sum(cols.values())
        if total > avail and total > 0:
            self.cols = {k: max(6, int(avail * v / total)) for k, v in cols.items()}
        else:
            self.cols = dict(cols)
        self.index   = index
        self.file    = file
        self._count  = 0

    def _iw(self) -> int:
        return 4 if self.index else 0

    def _sep(self, l, m, r) -> str:
        return _hsep(list(self.cols.values()), l, m, r, self._iw())

    def start(self) -> None:
        hc, hw = [], []
        if self.index:
            hc.append(c(BOLD + DEFAULT_LABEL, "#"))
            hw.append(self._iw())
        for name, w in self.cols.items():
            hc.append(c(BOLD + DEFAULT_LABEL, _trunc(name, w)))
            hw.append(w)
        print(self._sep("╭", "┬", "╮"), file=self.file)
        print(_row_str(hc, hw), file=self.file)
        print(self._sep("├", "┼", "┤"), file=self.file)
        self.file.flush()

    def row(self, data: dict) -> None:
        cells, cw = [], []
        if self.index:
            cells.append(c(DEFAULT_INDEX, str(self._count)))
            cw.append(self._iw())
        for name, w in self.cols.items():
            raw = str(data.get(name, ""))
            val = _trunc(resolve(name, raw, data), w)
            cells.append(val)
            cw.append(w)
        if self._count > 0:
            print(self._sep("├", "┼", "┤"), file=self.file)
        print(_row_str(cells, cw), file=self.file)
        self.file.flush()
        self._count += 1

    def end(self) -> None:
        print(self._sep("╰", "┴", "╯"), file=self.file)
        self.file.flush()