"""
lib/cleanup.py — Signal-safe cleanup stack for privileged resources.
Ensures mounts, loop devices, cgroups, and veth pairs are cleaned up
on SIGINT/SIGTERM or unhandled exceptions.
"""

import atexit
import os
import signal
import sys

_cleanup_stack = []
_original_sigint = signal.getsignal(signal.SIGINT)
_original_sigterm = signal.getsignal(signal.SIGTERM)


def register_cleanup(fn, *args):
    """Push a cleanup action onto the stack. LIFO order on teardown."""
    _cleanup_stack.append((fn, args))


def unregister_cleanup(fn, *args):
    """Remove a specific cleanup entry (e.g. after successful teardown)."""
    try:
        _cleanup_stack.remove((fn, args))
    except ValueError:
        pass


def _run_cleanup(signum=None, frame=None):
    """Execute all registered cleanups in reverse order, then exit if signaled."""
    while _cleanup_stack:
        fn, args = _cleanup_stack.pop()
        try:
            fn(*args)
        except Exception:
            pass
    if signum is not None:
        sys.exit(128 + signum)


def install_handlers():
    """Install signal handlers and atexit hook. Call once at startup."""
    atexit.register(_run_cleanup)
    signal.signal(signal.SIGTERM, _run_cleanup)
    signal.signal(signal.SIGINT, _run_cleanup)
