"""
common/emit.py — backwards-compat shim
"""
from common.emitter import (
    emit, set_mode, get_mode,
    enable_debug, is_debug,
    start_buffer, flush_buffer,
    _emitter,
)
from common.ir import to_public, register_event, clean_rows

__all__ = [
    "emit", "set_mode", "get_mode",
    "enable_debug", "is_debug",
    "start_buffer", "flush_buffer",
    "_emitter", "to_public", "register_event", "clean_rows",
]