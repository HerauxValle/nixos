"""
cli/handlers/image.py — image and select handlers
"""

import os
from common.emit import emit


def select(path: str, depth: int = 3) -> None:
    from cli.handlers._core import _select_img
    if path == "latest":
        from engine.image.scanner import scan_for_imgs
        from engine.image.selector import pick_best
        candidates = scan_for_imgs(max_depth=depth)
        chosen = pick_best(candidates)
        if chosen is None:
            from common.errors import error
            error("NOT_FOUND", "no img found", f"searched up to depth {depth}")
        path = chosen
        emit("log", f"resolved 'latest' → {os.path.basename(path)}")
    if not ("/" in path or path.endswith(".img") or os.path.exists(path)):
        from engine.image.select import _search_img
        matches = _search_img(path, depth)
        if matches:
            path = os.path.abspath(matches[0])
    else:
        path = os.path.abspath(path)
    _select_img(path, depth=depth)
    from engine.image.header import update_last_used
    update_last_used(path)
    try:
        from engine.container.stop import cleanup_stale
        from common.session import get_active
        cleanup_stale(get_active())
    except Exception:
        pass


def create_image(a) -> None:
    from common.errors import error
    from cli.handlers._core import create, parse_size
    path = os.path.expanduser(a.path or ".")
    if path.endswith(".img"):
        img_path = path
    elif a.name:
        img_path = f"{path}/{a.name}.img"
    else:
        error("MISSING_NAME", "provide -name or a direct .img path")
    create(img_path, size_mb=parse_size(a.size) if a.size else None, compress=bool(a.compress))
