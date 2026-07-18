#!/usr/bin/env python3
# Shared by redact.py/replace.py (the entries actually applied) and
# preflight_check.py (the "does this still match" check) so both sides
# resolve an entry's optional `line` field identically -- same reasoning
# as preflight_check.py importing find_matches from exclude.py directly,
# a real sibling-file import rather than duplicated logic that could
# silently drift apart.
#
# `line` is JSON-decoded from a Nix option typed `nullOr (either int
# (listOf int))`: null (unscoped, prior behavior), a bare int, or a list
# of ints. Normalized here to either None (unscoped -- every match in the
# file, prior behavior) or a set of 1-indexed line numbers.


def line_set(line):
    if line is None:
        return None
    if isinstance(line, list):
        return set(line)
    return {line}
