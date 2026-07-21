"""
engine/image/resolver.py — top-level img resolution: env var → scan → score
"""

import os

from lib.variables.general import IMG_ENV_VAR
from engine.image.scanner import scan_for_imgs
from engine.image.selector import pick_best


def resolve_img() -> str | None:
    """
    Return path to best available .img, or None.

    Priority:
      1. IMG_ENV_VAR env var (if set and file exists)
      2. Scan $HOME and score by header
      3. None
    """
    env = os.environ.get(IMG_ENV_VAR)
    if env and os.path.isfile(env):
        return env
    candidates = scan_for_imgs()
    return pick_best(candidates)
