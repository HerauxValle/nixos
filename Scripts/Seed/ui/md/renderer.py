"""
core/md/renderer.py — markdown renderer for terminal
"""
from common.emit import emit

import re
import os
from lib.variables.colors import (
    c, BOLD, DIM, ITALIC,
    BWHITE, WHITE, BBLACK, CYAN, BCYAN,
    GREEN, YELLOW, BYELLOW, TEAL
)


def _term_width() -> int:
    try:
        return os.get_terminal_size().columns
    except OSError:
        return 100


def _strip_ansi(s: str) -> str:
    return re.sub(r"\033\[[0-9;]*m", "", s)


def _vis(s: str) -> int:
    return len(_strip_ansi(s))


def _inline(text: str) -> str:
    text = re.sub(r"`(.+?)`",        lambda m: c(BCYAN,         m.group(1)), text)
    text = re.sub(r"\*\*(.+?)\*\*", lambda m: c(BOLD + BWHITE, m.group(1)), text)
    text = re.sub(r"__(.+?)__",     lambda m: c(BOLD + BWHITE, m.group(1)), text)
    text = re.sub(r"\*(.+?)\*",     lambda m: c(DIM + WHITE,   m.group(1)), text)
    text = re.sub(r"_(.+?)_",       lambda m: c(DIM + WHITE,   m.group(1)), text)
    text = re.sub(
        r"\[(.+?)\]\((.+?)\)",
        lambda m: c(CYAN, m.group(1)) + c(BBLACK, f" → {m.group(2)}"),
        text
    )
    return text


def _colorize_line(line: str) -> str:
    if re.match(r"\s*#", line):
        return c(BBLACK, line)
    if re.match(r"\s*\[.+\]", line):
        return c(CYAN, line)
    if "=" in line:
        k, _, v = line.partition("=")
        v = re.sub(r'"([^"]*)"', lambda m: c(YELLOW, f'"{m.group(1)}"'), v)
        return c(TEAL, k) + c(BBLACK, "=") + c(GREEN, v)
    return c(GREEN, line)


def _code_block(lines: list[str], lang: str) -> str:
    w         = _term_width()
    ln_w      = len(str(len(lines)))
    ln_prefix = ln_w + 1                         # "N " visible width
    content_w = min(
        max((len(l) for l in lines), default=0) + ln_prefix,
        w - 4
    )
    fill_w = content_w + 2

    if lang:
        lang_part = f" {lang} "
        top = c(BBLACK, "╭" + lang_part + "─" * max(0, fill_w - len(lang_part)) + "╮")
    else:
        top = c(BBLACK, "╭" + "─" * fill_w + "╮")

    bottom = c(BBLACK, "╰" + "─" * fill_w + "╯")
    div    = c(BBLACK, "│")

    out = ["", top]
    for lineno, line in enumerate(lines, 1):
        ln      = c(BBLACK, f"{lineno:{ln_w}} ")
        colored = _colorize_line(line)
        vis     = ln_prefix + _vis(colored)
        padding = " " * max(0, content_w - vis)
        out.append(f"{div} {ln}{colored}{padding} {div}")
    out.extend([bottom, ""])
    return "\n".join(out)


HEADER_STYLES = {
    1: lambda t, w: f"\n{c(BYELLOW, '━' * min(w, 80))}\n{c(BOLD + BYELLOW, t)}\n{c(BYELLOW, '━' * min(w, 80))}",
    2: lambda t, w: f"\n{c(BOLD + CYAN, t)}\n{c(BBLACK, '─' * min(len(_strip_ansi(t)), w))}",
    3: lambda t, w: f"\n{c(BOLD + BWHITE, t)}",
    4: lambda t, w: f"  {c(BOLD + BBLACK, t)}",
    5: lambda t, w: f"  {c(BBLACK, t)}",
    6: lambda t, w: f"  {c(BBLACK, t)}",
}


class _Printer:
    """Wraps print to prepend global line numbers."""
    def __init__(self, total_lines: int):
        self._n   = 0
        self._w   = len(str(total_lines))

    def __call__(self, text: str = "") -> None:
        # handle multi-line strings (e.g. code blocks, h1)
        for part in text.split("\n"):
            self._n += 1
            prefix = c(BBLACK, f"{self._n:{self._w}}  ")
            print(prefix + part)


def render(text: str) -> None:
    lines      = text.splitlines()
    w          = _term_width()
    i          = 0
    in_code    = False
    code_lines: list[str] = []
    code_lang  = ""
    out        = _Printer(len(lines) * 3)   # rough upper bound

    while i < len(lines):
        line     = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            if in_code:
                emit("action", _code_block(code_lines, code_lang))
                code_lines = []
                code_lang  = ""
                in_code    = False
            else:
                code_lang = stripped[3:].strip()
                in_code   = True
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        if not stripped:
            emit("action", )
            i += 1
            continue

        if re.match(r"^[-*_]{3,}$", stripped):
            emit("action", c(BBLACK, "─" * (w - out._w - 2)))
            i += 1
            continue

        m = re.match(r"^(#{1,6})\s+(.*)", line)
        if m:
            level = len(m.group(1))
            text  = _inline(m.group(2))
            fmt   = HEADER_STYLES.get(level, HEADER_STYLES[6])
            emit("action", fmt(text, w - out._w - 2))
            i += 1
            continue

        if stripped.startswith(">"):
            emit("action", c(BBLACK, "┃ ") + c(DIM + WHITE, _inline(stripped[1:].strip())))
            i += 1
            continue

        m = re.match(r"^(\s*)[-*+]\s+(.*)", line)
        if m:
            depth  = len(m.group(1)) // 2
            bullet = [c(CYAN, "•"), c(BBLACK, "◦"), c(BBLACK, "▸")][min(depth, 2)]
            emit("action", "  " * depth + f" {bullet} {_inline(m.group(2))}")
            i += 1
            continue

        m = re.match(r"^(\s*)(\d+)\.\s+(.*)", line)
        if m:
            depth = len(m.group(1)) // 2
            num   = m.group(2)
            emit("action", "  " * depth + f" {c(CYAN, num + '.')} {_inline(m.group(3))}")
            i += 1
            continue

        emit("action", _inline(line))
        i += 1


def render_file(path: str) -> None:
    with open(path, "r", encoding="utf-8") as f:
        render(f.read())