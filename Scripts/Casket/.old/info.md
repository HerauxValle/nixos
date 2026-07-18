<!-- &desc: "Deprecation notice for the original Python cas implementation, kept here for reference only." -->
# Deprecated: Python `cas`

`main.py` is the original implementation of `cas`, replaced by the Rust
rewrite in `../src/`. It still runs (`python3 main.py ...`) and is
byte-compatible with the Rust version's vault format — the on-disk
metadata trailer is identical, so a vault opened/modified with one is
fully readable by the other.

**It will not receive further updates**, and carries at least two known
bugs that the rewrite fixes (see `../docs/porting-notes.md` for detail):

- `cas <vault> info` always reports 0 active LUKS key slots.
- `cas <vault> rename` with no argument silently renames the vault to
  `rename.img` instead of erroring.

`cas` on `PATH` now resolves to the compiled Rust binary (wired via
`Nixos/config/software/packages/{registry,packages}.nix`, packaged in
`../flake.nix`). This file exists purely as a paper trail for why
`main.py` moved here instead of being deleted outright.
