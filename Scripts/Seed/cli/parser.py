"""
cli/parser.py — lightweight argv parser, replaces argparse
"""

import sys
from dataclasses import dataclass, field


@dataclass
class Cmd:
    positionals: list[str]          = field(default_factory=list)  # "name", "path?", "cmd..."
    flags:       list[str]          = field(default_factory=list)   # "-f/flag", "-n/int=3", "-e"
    func:        object             = None
    dispatch:    dict               = None                          # {target: callable}


def cmd(*positionals, flags="", func=None, dispatch=None) -> Cmd:
    return Cmd(
        positionals = list(positionals),
        flags       = [f.strip() for f in flags.split() if f.strip()],
        func        = func,
        dispatch    = dispatch,
    )


class NS:
    """Namespace for parsed args. Only declared attributes return None; typos raise."""

    def __init__(self):
        super().__setattr__("_declared", set())

    def __getattr__(self, k):
        if k.startswith("_") or k in self._declared:
            return None
        raise AttributeError(f"NS has no attribute '{k}' (did you misspell it?)")

    def __setattr__(self, k, v):
        if not k.startswith("_"):
            self._declared.add(k)
        super().__setattr__(k, v)


def _parse_flag_spec(spec: str) -> tuple[list[str], str, str, object]:
    """
    Parse a flag spec string into (names, dest, kind, default).
    Type annotation is the last segment only if it doesn't start with '-'.
    Examples:
      "-f/flag"         → (["-f"],          "f",      "flag", False)
      "-lines/int=50"   → (["-lines"],      "lines",  "int",  50)
      "--all/flag"      → (["--all"],       "all",    "flag", False)
      "-name/-n"        → (["-name","-n"],  "name",   "str",  None)
      "-size/-s"        → (["-size","-s"],  "size",   "str",  None)
      "-e"              → (["-e"],          "e",      "str",  None)
    """
    parts = spec.split("/")
    # last part is type annotation if it doesn't start with "-"
    if len(parts) > 1 and not parts[-1].startswith("-"):
        type_part  = parts[-1]
        names      = parts[:-1]
    else:
        type_part  = "str"
        names      = parts

    default = None
    kind    = "str"

    if "=" in type_part:
        kind, _, raw_default = type_part.partition("=")
        default = int(raw_default) if kind == "int" else raw_default
    else:
        kind = type_part

    if kind == "flag":
        default = False

    dest = max(names, key=len).lstrip("-").replace("-", "_")
    return names, dest, kind, default


def _parse_argv(argv: list[str], spec: Cmd) -> NS:
    ns      = NS()
    args    = list(argv)
    pos_idx = 0

    # build flag lookup: "-f" → (dest, kind, default)
    flag_map = {}
    for fspec in spec.flags:
        names, dest, kind, default = _parse_flag_spec(fspec)
        setattr(ns, dest, default)
        for name in names:
            flag_map[name] = (dest, kind)

    # set positional defaults
    for p in spec.positionals:
        if p.endswith("..."):
            setattr(ns, p.rstrip("."), [])
        elif p.endswith("?"):
            setattr(ns, p.rstrip("?"), None)

    i = 0
    while i < len(args):
        tok = args[i]

        if tok.startswith("-") and tok not in flag_map:
            from common.errors import error
            error("UNKNOWN_FLAG", f"unknown flag '{tok}'")

        if tok in flag_map:
            dest, kind = flag_map[tok]
            if kind == "flag":
                setattr(ns, dest, True)
            elif kind == "int":
                i += 1
                setattr(ns, dest, int(args[i]))
            else:
                i += 1
                setattr(ns, dest, args[i])
            i += 1
            continue

        # positional
        if pos_idx < len(spec.positionals):
            pname = spec.positionals[pos_idx]
            if pname.endswith("..."):
                setattr(ns, pname.rstrip("."), args[i:])
                break
            elif pname.endswith("?"):
                setattr(ns, pname.rstrip("?"), tok)
            else:
                setattr(ns, pname, tok)
            pos_idx += 1
        i += 1

    return ns


def parse(schema: dict, argv: list[str]) -> tuple[object, NS] | None:
    """
    Parse argv against schema. Returns (func, ns) or exits on error.
    func is either a callable or a dispatch dict lookup.
    """
    from common.errors import error

    if argv and argv[0] in ("-h",):
        return None, NS()
    if not argv:
        from common.errors import error
        error("NO_CMD", "no command given", "run 'sd help' for available commands")

    cmd_name = argv[0]
    if cmd_name not in schema:
        error("UNKNOWN_CMD", f"unknown command '{cmd_name}'",
              f"run 'sd help' for available commands")

    spec = schema[cmd_name]
    ns   = _parse_argv(argv[1:], spec)

    if spec.dispatch:
        target = getattr(ns, "target", None) or getattr(ns, spec.positionals[0] if spec.positionals else "", None)
        if target not in spec.dispatch:
            error("UNKNOWN_TARGET", f"unknown target '{target}' for '{cmd_name}'",
                  f"valid: {', '.join(spec.dispatch.keys())}")
        if spec.func:
            func = spec.func
        else:
            func = lambda a, t=target, d=spec.dispatch: d[t](a)
    else:
        func = spec.func

    return func, ns