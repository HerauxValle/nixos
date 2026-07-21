"""
lib/fuzzy.py — Fuzzy matching with ... wildcard expansion
Supports: "n8n...", "...n8n", "...n8n...", etc.
"""

import difflib


def normalize_pattern(pattern: str) -> tuple[str, bool, bool]:
    """
    Parse pattern like "n8n..." or "...n8n" into (core, has_prefix, has_suffix).
    Returns (search_term, starts_with_dots, ends_with_dots)
    """
    has_prefix = pattern.startswith("...")
    has_suffix = pattern.endswith("...")

    core = pattern.replace("...", "").strip()

    return core, has_prefix, has_suffix


def fuzzy_match(pattern: str, candidates: list[str]) -> list[str]:
    """
    Fuzzy match pattern against candidates.

    - "n8n" → exact substring match
    - "n8n..." → starts with "n8n"
    - "...n8n" → ends with "n8n"
    - "...n8n..." → contains "n8n" anywhere
    - "n8..." → fuzzy match starting with "n8"

    Returns list of matches sorted by relevance.
    """
    if not pattern or not candidates:
        return []

    core, has_prefix, has_suffix = normalize_pattern(pattern)

    if not core:
        return candidates  # "..." matches all

    matches = []

    for candidate in candidates:
        # Exact substring match
        if core in candidate:
            matches.append((candidate, 100))
            continue

        # Fuzzy match using difflib
        ratio = difflib.SequenceMatcher(None, core.lower(), candidate.lower()).ratio()
        if ratio > 0.5:  # At least 50% match
            matches.append((candidate, int(ratio * 100)))

    # Sort by score (descending), then alphabetically
    matches.sort(key=lambda x: (-x[1], x[0]))
    return [m[0] for m in matches]


def expand_arg(arg: str, available: list[str]) -> str:
    """
    Expand arg if it contains ... wildcard.
    If multiple matches, return first (most relevant).
    If no matches, return original arg.
    """
    if "..." not in arg:
        return arg

    matches = fuzzy_match(arg, available)
    return matches[0] if matches else arg
