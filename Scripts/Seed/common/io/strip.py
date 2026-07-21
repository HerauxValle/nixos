"""
common/io/strip.py — JSONC comment stripper
Single source of truth. Handles // line comments and /* */ blocks
without touching strings or URLs.
"""

__all__ = ["jsonc"]


def jsonc(text: str) -> str:
    """Strip // and /* */ comments from JSONC. Safe for strings and URLs."""
    result = []
    i      = 0
    in_str = False
    n      = len(text)

    while i < n:
        c = text[i]

        if in_str:
            if c == "\\" and i + 1 < n:
                result.append(c)
                result.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            result.append(c)

        else:
            if c == '"':
                in_str = True
                result.append(c)
            elif text[i:i+2] == "//":
                while i < n and text[i] != "\n":
                    i += 1
                continue
            elif text[i:i+2] == "/*":
                i += 2
                while i < n and text[i:i+2] != "*/":
                    i += 1
                i += 2
                continue
            else:
                result.append(c)

        i += 1

    return "".join(result)