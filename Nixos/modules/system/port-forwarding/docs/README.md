# port-forwarding docs

- [`mapping.md`](./mapping.md) -- every pmg feature and exactly what it
  became here: a native NixOS option, a reimplemented service, or a
  runtime-only activation step, and why each landed where it did.
- [`architecture.md`](./architecture.md) -- how the pieces fit together:
  the entry schema, why the top-level wiring file is one flat attrset
  instead of a `lib.mkMerge` list, how a service's lifecycle gets bound
  without reimplementing pmg's own watcher, and the pure-eval constraint
  that shapes several of these decisions.
- [`decisions.md`](./decisions.md) -- the specific, sometimes-non-obvious
  calls made building this, and the concrete thing (a live test, a real
  bug) that justified each one.
- [`stubs.md`](./stubs.md) -- why every fragment directory has a
  `_stub.py`, and why it's inert -- never read by Nix, never executed.

For the actual option reference, see `glossar/system/port-forwarding.nix`
(every field, commented out, copy-paste ready) or `default.nix`'s own
option descriptions. This directory is design rationale, not a field
reference.
