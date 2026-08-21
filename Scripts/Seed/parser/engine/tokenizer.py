"""
core/parser/tokenizer.py — converts raw text into a token stream
using a Ruleset to know what to look for.
"""

import re
from dataclasses import dataclass, field
from enum import Enum, auto

from parser.engine.ruleset import Ruleset


class TType(Enum):
    BLOCK_OPEN   = auto()  # [key]:[
    BLOCK_CLOSE  = auto()  # ]: or ]:]:
    DECLARATION  = auto()  # [key] = value
    KV           = auto()  # key = value
    RAW          = auto()  # raw line inside raw block
    COMMENT      = auto()  # # ...
    BLANK        = auto()  # empty line
    SHEBANG      = auto()  # #!format


@dataclass
class Token:
    type:    TType
    value:   str              # raw matched line
    capture: list[str]        # captured groups from regex
    lineno:  int
    indent:  int              # leading whitespace count


def tokenize(text: str, ruleset: Ruleset) -> list[Token]:
    tokens  = []
    lines   = text.splitlines()
    in_ml_comment = False
    in_raw_block  = False
    raw_block_depth = 0
    block_stack: list[str] = []  # track current block names

    re_block_open  = re.compile(ruleset.tok_block_open)
    re_block_close = re.compile(ruleset.tok_block_close)
    re_declaration = re.compile(ruleset.tok_declaration)
    re_kv          = re.compile(ruleset.tok_kv)

    def _indent(line: str) -> int:
        return len(line) - len(line.lstrip())

    def _strip(line: str) -> str:
        if ruleset.ws_trailing == "strip":
            return line.rstrip()
        return line

    def _strip_inline_comment(line: str) -> str:
        if ruleset.tok_inline_comment:
            idx = line.find(ruleset.tok_comment)
            if idx > 0:
                return line[:idx].rstrip()
        return line

    for lineno, raw in enumerate(lines, 1):
        line    = _strip(raw)
        indent  = _indent(line)
        stripped = line.strip()

        # multiline comment handling
        if in_ml_comment:
            if stripped == ruleset.tok_ml_comment_close:
                in_ml_comment = False
            tokens.append(Token(TType.COMMENT, line, [], lineno, indent))
            continue

        if stripped == ruleset.tok_ml_comment_open:
            in_ml_comment = True
            tokens.append(Token(TType.COMMENT, line, [], lineno, indent))
            continue

        # blank line
        if not stripped:
            tokens.append(Token(TType.BLANK, line, [], lineno, indent))
            continue

        # shebang — only on line 1
        if lineno == 1 and ruleset.shebang_enabled and stripped.startswith(ruleset.shebang_marker):
            fmt = stripped[len(ruleset.shebang_marker):].strip()
            tokens.append(Token(TType.SHEBANG, line, [fmt], lineno, indent))
            continue

        # single line comment
        if stripped.startswith(ruleset.tok_comment):
            tokens.append(Token(TType.COMMENT, line, [], lineno, indent))
            continue

        # raw block — pass lines through until block_close
        if in_raw_block:
            # check for block close(s)
            close_line = stripped
            closes = 0
            while re_block_close.match(close_line):
                closes += 1
                close_line = close_line[len(re_block_close.match(close_line).group()):]
                if not ruleset.tok_block_chain:
                    break

            if closes > 0:
                in_raw_block = False
                for _ in range(closes):
                    if block_stack:
                        block_stack.pop()
                tokens.append(Token(TType.BLOCK_CLOSE, line, [str(closes)], lineno, indent))
                continue

            tokens.append(Token(TType.RAW, line, [line], lineno, indent))
            continue

        # block close(s)
        close_line = stripped
        closes = 0
        temp   = close_line
        while re_block_close.match(temp):
            m = re_block_close.match(temp)
            closes += 1
            temp = temp[len(m.group()):]
            if not ruleset.tok_block_chain:
                break

        if closes > 0:
            for _ in range(closes):
                if block_stack:
                    block_stack.pop()
            tokens.append(Token(TType.BLOCK_CLOSE, line, [str(closes)], lineno, indent))
            continue

        # block open
        m = re_block_open.match(stripped)
        if m:
            name = m.group(1).strip()
            key  = name if ruleset.blk_case_sensitive else name.lower()
            block_stack.append(key)
            if key in [b.lower() for b in ruleset.blk_raw]:
                in_raw_block = True
            tokens.append(Token(TType.BLOCK_OPEN, line, [key], lineno, indent))
            continue

        # top-level declaration [key] = value
        m = re_declaration.match(stripped)
        if m and not block_stack:
            tokens.append(Token(TType.DECLARATION, line, [m.group(1).strip(), m.group(2).strip()], lineno, indent))
            continue

        # kv
        clean = _strip_inline_comment(stripped)
        m = re_kv.match(clean)
        if m:
            tokens.append(Token(TType.KV, line, [m.group(1).strip(), m.group(2).strip()], lineno, indent))
            continue

        # fallback — raw line
        tokens.append(Token(TType.RAW, line, [line], lineno, indent))

    if ruleset.dbg_tokens:
        for t in tokens:
            print(f"  [token] {t.type.name:15} ln{t.lineno:3}  {t.capture}")

    return tokens