"""
common/emitter.py — Emitter class + shared instance
Pipeline: emit() → normalize() → IR → dispatch() → renderer.render(IR)
"""
import sys
from typing import Any

from common.ir import (
    _normalize, _validate, _fill_keys, _apply_meta,
    clean_rows, to_public, register_event,
    _EVENT_MAP, _META_KEYS,
)

# ── Emitter ───────────────────────────────────────────────────────────────────

class Emitter:
    def __init__(self):
        self.mode     = "table"   # table | verbose | json
        self.debug    = False
        self.ansi     = self._detect_ansi()
        self.max_rows = 0         # 0 = unlimited; set via meta={"max_rows": N}
        self._buffer: list[dict] = []
        self._buffering = False

    @staticmethod
    def _detect_ansi() -> bool:
        """True if terminal supports ANSI color codes."""
        import os
        if os.environ.get("NO_COLOR"):       return False
        if os.environ.get("FORCE_COLOR"):    return True
        if not sys.stdout.isatty():          return False
        term = os.environ.get("TERM", "")
        if term in ("dumb", ""):             return False
        return True

    # ── public config ─────────────────────────────────────────────────────────

    def set_mode(self, mode: str) -> None:
        assert mode in ("table", "verbose", "json"), f"unknown mode: {mode}"
        self.mode = mode

    def get_mode(self) -> str:
        return self.mode

    def enable_debug(self) -> None:
        self.debug = True

    def is_debug(self) -> bool:
        return self.debug

    # ── buffer control ────────────────────────────────────────────────────────

    def start_buffer(self) -> None:
        self._buffering = True
        self._buffer    = []

    def flush_buffer(self) -> None:
        self._buffering = False
        if self.mode == "json" and self._buffer:
            # wrap all buffered IRs as JSON array for valid piping
            from common.renderers.json_ import JsonRenderer
            import sys, json
            from common.ir import to_public
            out = [to_public(ir) for ir in self._buffer]
            print(json.dumps(out, indent=2, default=str), file=sys.stdout)
        else:
            for ir in self._buffer:
                self._render(ir)
        self._buffer = []

    # ── main entry ────────────────────────────────────────────────────────────

    def emit(self, type_: str, *args: Any, **kwargs) -> None:
        ir = _normalize(type_, args, kwargs)

        # suppress log unless debug
        if ir["type"] == "log" and not self.debug:
            return

        # fill union keys on rows
        _validate(ir)
        ir["rows"] = _fill_keys(ir["rows"])
        ir = _apply_meta(ir)

        meta     = ir.get("meta", {})
        stream   = meta.pop("stream", False)
        priority = meta.pop("priority", None)
        # auto-assign priority by type
        if priority is None:
            priority = "high" if ir["type"] == "error" else                        "medium" if ir["type"] == "warning" else "normal"
        if stream: meta["_stream"] = True
        # high priority: never buffer, render immediately
        if self._buffering and priority == "normal" and not stream:
            self._buffer.append(ir)
        else:
            self._render(ir)

    # ── dispatch → renderer ───────────────────────────────────────────────────

    def _render(self, ir: dict) -> None:
        # composable sections: render label then recurse into children
        if ir.get("type") == "section":
            label_ir = {"type": "action", "v": 1,
                        "rows": ir["rows"], "meta": {}}
            self._render(label_ir)
            for child in ir.get("children", []):
                self._render(child)
            return
        if ir.get("meta", {}).get("_stream"):
            self._render_stream(ir)
            return
        renderer = self._get_renderer()
        try:
            renderer.render(ir)
        except Exception as e:
            import traceback
            print(f"[render error: {e}]", file=sys.stderr)
            traceback.print_exc(file=sys.stderr)
            if self.debug:
                sys.exit(1)

    def _render_stream(self, ir: dict) -> None:
        from common.renderers.live import LiveTable
        rows = ir["rows"]
        if not rows: return
        cols = {k: max(len(k), max(len(str(r.get(k,""))) for r in rows))
                for k in rows[0] if not k.startswith("_")}
        lt = LiveTable(cols)
        lt.start()
        for row in rows: lt.row(row)
        lt.end()

    def _get_renderer(self):
        # check registry first — allows custom renderer modes
        from common.renderers import get_renderer_class
        cls = get_renderer_class(self.mode)
        if cls:
            return cls()
        if self.mode == "verbose":
            from common.renderers.verbose import VerboseRenderer
            return VerboseRenderer()
        elif self.mode == "json":
            from common.renderers.json_ import JsonRenderer
            return JsonRenderer()
        else:
            from common.renderers.table import TableRenderer
            return TableRenderer()




# ── shared instance ───────────────────────────────────────────────────────────

_emitter = Emitter()


def emit(type_: str, *args: Any, **kwargs) -> None:
    _emitter.emit(type_, *args, **kwargs)

def set_mode(mode: str) -> None:      _emitter.set_mode(mode)
def get_mode() -> str:                return _emitter.get_mode()
def enable_debug() -> None:           _emitter.enable_debug()
def is_debug() -> bool:               return _emitter.is_debug()
def start_buffer() -> None:           _emitter.start_buffer()
def flush_buffer() -> None:           _emitter.flush_buffer()