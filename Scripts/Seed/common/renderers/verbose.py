"""
common/renderers/verbose.py — VerboseRenderer
Plain text, respects terminal width. No borders.
"""
import sys
import os


def _term_w() -> int:
    try: return os.get_terminal_size().columns
    except OSError: return 120


def _trunc_plain(s: str, w: int) -> str:
    return s if len(s) <= w else s[:max(0, w - 3)] + "..."


class VerboseRenderer:
    def render(self, ir: dict, file=sys.stdout) -> None:
        t    = ir["type"]
        rows = ir["rows"]
        w    = _term_w()

        if t == "log":
            for r in rows:
                print(f"  {r.get('message', '')}", file=file, flush=True)
            return

        if t == "error":
            file = sys.stderr
            for r in rows:
                code = r.get("code", "")
                msg  = r.get("message", "")
                det  = r.get("detail", "")
                line = f"error [{code}]: {msg}" + (f" — {det}" if det else "")
                print(_trunc_plain(line, w), file=file)
            return

        for r in rows:
            if "__section__" in r:
                label = r["__section__"]
                if label: print(f"\n── {_trunc_plain(str(label), w - 4)} ──", file=file)
                continue
            if "_meta" in r:
                continue
            cols = [k for k in r if not k.startswith("_") and k != "__section__"]
            parts = [str(r.get(k, "")) for k in cols if str(r.get(k, "")).strip()]
            line  = "  ".join(parts)
            print(_trunc_plain(line, w), file=file)