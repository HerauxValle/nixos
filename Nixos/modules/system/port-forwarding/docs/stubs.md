<!-- &desc: "Port-forwarding Python fragments _stub.py guide -- type stubs for linter (concatenated .py fragments reference undefined names), test-harness module interface." -->

# Why every fragment directory has a `_stub.py`

`lib/cert/`, `lib/ipv6-bridge/`, `lib/mdns/`, and `lib/router/` each
assemble their real script by concatenating that directory's own
`.py` fragment files together at build time (see `decisions.md`'s own
"Python scripts are concatenated fragments" section). That means a
fragment like `ipv6-bridge/handler.py` uses names -- `PORT`, `MODE`,
`TLS_CTX`, `rewrite_request`, `relay` -- that don't actually exist
anywhere in that file. They're real once every fragment plus
`preamble.nix`'s Nix-generated constants land in the same concatenated
script, but a linter/LSP (pyright, pylance, ...) only ever sees one
file at a time and correctly flags them as undefined.

`_stub.py` fixes that without touching the Nix wiring or runtime
behavior at all:

```python
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import PORT, MODE, TLS_CTX, relay, rewrite_request
```

`TYPE_CHECKING` is a constant from the standard library `typing`
module that's always `False` at runtime -- Python itself never enters
that branch, so this import is never actually attempted and can't
fail even though `_stub.py` is never concatenated into the real
script and no such module exists on `sys.path` when the assembled
script actually runs. A type checker, on the other hand, treats
`TYPE_CHECKING` as `True` and resolves the import for real, against
`_stub.py`'s declarations:

```python
# lib/ipv6-bridge/_stub.py
PORT: int
MODE: str
TLS_CTX: Optional[ssl.SSLContext]

def relay(src, dst) -> None: ...
def rewrite_request(buf, client_ip, scheme): ...
```

Each `_stub.py` is a plain declaration file -- bare annotations for
the constants `preamble.nix` generates, `def f(...): ...` stubs for
functions defined in a sibling fragment -- one per directory, never
referenced by that directory's own `default.nix` (confirmed: nothing
in any `fragments = [...]` list or `builtins.readFile` call points at
it), so it can't end up duplicated into the real assembled script the
way the fragments' own stdlib `import` lines harmlessly do.

Only fragments that actually reference a cross-fragment name get the
`if TYPE_CHECKING:` block -- e.g. `ipv6-bridge/wait-backend.py` and
`relay.py` use only their own locals/params, so they have none.
