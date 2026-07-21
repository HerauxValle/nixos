#!/usr/bin/env python3
"""
main.py — sd entry point
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cli.commands  import register
from common.errors import error
from common.emit   import set_mode, start_buffer, flush_buffer
from lib.variables.general import *


def _setup_signals() -> None:
    """SIGWINCH: invalidate terminal width cache on resize. Install cleanup handlers."""
    import signal
    try:
        from ui.table.primitives import invalidate_term_width
        signal.signal(signal.SIGWINCH, lambda *_: invalidate_term_width())
    except Exception:
        pass
    from lib.cleanup import install_handlers
    install_handlers()


def main():
    _setup_signals()
    argv = sys.argv[1:]

    # strip debug flag
    debug = DEBUG_FLAG in argv
    if debug:
        argv = [a for a in argv if a != DEBUG_FLAG]

    # strip mode flags (-t / -n / -j) — only from start of argv, before command
    cli_mode = None
    _mode_map = {**MODE_FLAGS, "-j": "json"}
    while argv and argv[0] in _mode_map:
        cli_mode = _mode_map[argv[0]]
        argv     = argv[1:]

    # resolve mode: cli flag > DEFAULT_MODE rule > default
    if cli_mode:
        set_mode(cli_mode)
    else:
        try:
            from orchestration.settings import get_rule
            rule = get_rule("DEFAULT_MODE")
            if rule and rule in VALID_MODES:
                set_mode(rule)
        except Exception:
            pass

    if debug:
        from common.emit import enable_debug
        enable_debug()

    # Expand ... fuzzy patterns in argv (only import when needed)
    if any("..." in a for a in argv):
        try:
            from cli.completion import expand_fuzzy_args
            from common.session import _session_key
            key = _session_key()
            path = f"{SESSIONS_BASE}/{key}"
            if os.path.isfile(path):
                mnt = open(path).read().strip()
                if os.path.isdir(mnt):
                    argv = expand_fuzzy_args(argv, mnt)
        except Exception:
            pass

    func, ns = register(argv)

    if func is None:
        from cli.help import show_help
        show_help()
        sys.exit(0)

    try:
        start_buffer()
        func(ns)
        flush_buffer()
    except KeyboardInterrupt:
        flush_buffer()
        print("\naborted")
        sys.exit(1)
    except Exception as e:
        flush_buffer()
        error("UNEXPECTED", str(e))


if __name__ == "__main__":
    main()