"""
engine/image/scanner.py — scan $HOME for valid .img files by header magic
"""

import os
from pathlib import Path

from lib.variables.general import IMG_SCAN_DEPTH
from engine.image.header import read_header


def scan_for_imgs(root: str | None = None, max_depth: int = IMG_SCAN_DEPTH) -> list[str]:
    """
    Walk root (default: $HOME) up to max_depth levels, finding .img files with valid headers.
    Only returns .img files with correct magic bytes and version (fresh imgs only).
    Skip hidden dirs (starting with '.') and symlinks.
    Never raises.
    """
    if root is None:
        root = os.path.expanduser("~")
    matches = []

    def _walk(path: Path, depth: int) -> None:
        if depth > max_depth:
            return
        try:
            entries = list(path.iterdir())
        except PermissionError:
            return
        for entry in entries:
            if entry.is_symlink():
                continue
            if entry.is_dir() and not entry.name.startswith("."):
                _walk(entry, depth + 1)
            elif entry.is_file() and entry.suffix == ".img":
                if read_header(str(entry)) is not None:
                    matches.append(str(entry))

    _walk(Path(root), 1)
    return matches
