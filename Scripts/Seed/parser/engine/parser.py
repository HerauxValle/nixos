"""
core/parser/parser.py — builds a tree from a token stream
"""

from dataclasses import dataclass, field
from parser.engine.tokenizer import Token, TType, tokenize
from parser.engine.ruleset   import Ruleset


@dataclass
class Node:
    name:     str
    kind:     str                        # "block", "declaration", "root"
    kv:       dict[str, object]          = field(default_factory=dict)
    raw:      list[str]                  = field(default_factory=list)
    children: list["Node"]              = field(default_factory=list)
    lineno:   int                        = 0


@dataclass
class ParseTree:
    root:         Node
    declarations: dict[str, object]     = field(default_factory=dict)
    shebang:      str | None            = None
    errors:       list[str]             = field(default_factory=list)
    warnings:     list[str]             = field(default_factory=list)


def _cast_value(raw: str, ruleset: Ruleset) -> object:
    v = raw.strip()

    # strip quotes
    if ruleset.val_quote and len(v) >= 2:
        q = ruleset.val_quote
        if v.startswith(q) and v.endswith(q):
            return v[1:-1]

    if ruleset.val_auto_none and v in ruleset.val_none:
        return None
    if ruleset.val_auto_bool:
        if v in ruleset.val_true:
            return True
        if v in ruleset.val_false:
            return False
    if ruleset.val_auto_int:
        try:
            return int(v)
        except ValueError:
            pass
    if ruleset.val_auto_float:
        try:
            return float(v)
        except ValueError:
            pass
    if ruleset.val_auto_list and v.startswith(ruleset.tok_list_open) and v.endswith(ruleset.tok_list_close):
        inner = v[1:-1]
        items = [i.strip() for i in inner.split(ruleset.tok_list_sep)]
        if ruleset.tok_list_trailing == "allow" and items and items[-1] == "":
            items = items[:-1]
        return [_cast_value(i, ruleset) for i in items]

    return v


def parse(tokens: list[Token], ruleset: Ruleset) -> ParseTree:
    root  = Node(name="root", kind="root")
    tree  = ParseTree(root=root)
    stack = [root]

    for tok in tokens:
        current = stack[-1]

        if tok.type == TType.SHEBANG:
            tree.shebang = tok.capture[0] if tok.capture else None

        elif tok.type in (TType.COMMENT, TType.BLANK):
            continue

        elif tok.type == TType.DECLARATION:
            key, val         = tok.capture
            tree.declarations[key] = _cast_value(val, ruleset)

        elif tok.type == TType.BLOCK_OPEN:
            name = tok.capture[0]
            node = Node(name=name, kind="block", lineno=tok.lineno)

            if not ruleset.blk_nested and len(stack) > 1:
                tree.errors.append(f"line {tok.lineno}: nested blocks not allowed ([{name}])")
                continue

            if len(stack) > ruleset.blk_max_depth:
                tree.errors.append(f"line {tok.lineno}: max nesting depth {ruleset.blk_max_depth} exceeded")
                continue

            current.children.append(node)
            stack.append(node)

        elif tok.type == TType.BLOCK_CLOSE:
            closes = int(tok.capture[0]) if tok.capture else 1
            for _ in range(closes):
                if len(stack) > 1:
                    stack.pop()
                else:
                    tree.errors.append(f"line {tok.lineno}: unexpected block close")

        elif tok.type == TType.KV:
            key, val = tok.capture
            cast     = _cast_value(val, ruleset)

            if ruleset.vld_duplicate_key in ("deny", "warn") and key in current.kv:
                msg = f"line {tok.lineno}: duplicate key '{key}' in [{current.name}]"
                if ruleset.vld_duplicate_key == "deny":
                    tree.errors.append(msg)
                else:
                    tree.warnings.append(msg)
                if ruleset.vld_duplicate_key != "override":
                    continue

            current.kv[key] = cast

        elif tok.type == TType.RAW:
            current.raw.append(tok.value)

    if ruleset.dbg_tree:
        _print_tree(root)

    return tree


def _print_tree(node: Node, depth: int = 0) -> None:
    indent = "  " * depth
    print(f"{indent}[{node.name}] ({node.kind})")
    for k, v in node.kv.items():
        print(f"{indent}  {k} = {v!r}")
    for line in node.raw:
        print(f"{indent}  | {line}")
    for child in node.children:
        _print_tree(child, depth + 1)


def parse_text(text: str, ruleset: Ruleset) -> ParseTree:
    tokens = tokenize(text, ruleset)
    return parse(tokens, ruleset)


def parse_file(path: str, ruleset: Ruleset) -> ParseTree:
    with open(path, "r", encoding=ruleset.enc_charset) as f:
        return parse_text(f.read(), ruleset)