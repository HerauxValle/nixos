"""
engine/image/selector.py — score and pick the best img from candidates
"""

import os
import time

from engine.image.header import read_header


def _score(path: str, header) -> float:
    """Score an img for auto-selection."""
    s = 0.0
    s += header.priority * 100_000  # priority dominates
    if header.last_used > 0:
        age = time.time() - header.last_used
        s += max(0.0, 50_000 - age)  # recency bonus
    try:
        s += os.path.getmtime(path)  # mtime tiebreaker
    except OSError:
        pass
    return s


def pick_best(candidates: list[str]) -> str | None:
    """Return the highest-scoring candidate, or None if empty."""
    if not candidates:
        return None
    if len(candidates) == 1:
        return candidates[0]

    scored = []
    for path in candidates:
        h = read_header(path)
        if h is not None:
            scored.append((_score(path, h), path))

    if not scored:
        return None

    scored.sort(reverse=True)
    return scored[0][1]
