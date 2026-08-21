"""
common/renderers/table.py — TableRenderer
Maps IR → core/table/ API. No table logic here.
"""
import sys
from ui.table import table as _table


class TableRenderer:
    def render(self, ir: dict, file=sys.stdout) -> None:
        t    = ir["type"]
        rows = ir["rows"]
        meta = ir.get("meta", {})

        if not rows:
            return

        if t in ("action", "warning"):
            _table(rows, file=file)

        elif t == "error":
            _table(rows, file=sys.stderr)

        elif t == "table":
            # meta["view"] maps to table(type=)
            kwargs = {}
            if "view"          in meta: kwargs["type"]          = meta["view"]
            if "tree_col"      in meta: kwargs["tree_col"]      = meta["tree_col"]
            if "by"            in meta: kwargs["by"]            = meta["by"]
            if "indicator_col" in meta: kwargs["indicator_col"] = meta["indicator_col"]
            if "right_rows"    in meta: kwargs["right_rows"]    = meta["right_rows"]
            if "renderers"     in meta: kwargs["renderers"]     = meta["renderers"]
            _table(rows, file=file, **kwargs)

        # log suppressed in table mode (handled by Emitter)