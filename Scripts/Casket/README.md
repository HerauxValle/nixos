<!-- &desc: "Top-level README: what cas is, how to build/run it, and where the rest of the docs live." -->
# cas — encrypted vault manager

A vault is a single `.img` file — a LUKS2 container — that mounts like a
folder once opened. Optional 2FA (a keyfile alongside your passphrase),
btrfs snapshots, safe passphrase rotation, and grow/shrink resizing, all
from one binary.

This is a Rust rewrite of the original Python `cas`, now on `PATH` as
the `casket` package (`Nixos/config/software/packages/`). The Python
original is deprecated but kept for reference at `.old/main.py` — see
`.old/info.md`. Full behavioral parity was the goal — every action,
flag, and message text carries over — plus two real bugs fixed and some
hardening. See `docs/porting-notes.md` for exactly what changed and why.

## Build

```sh
cargo build --release        # ./target/release/cas
```

or, via the flake:

```sh
nix build                    # ./result/bin/cas
nix develop                  # devShell with cargo/rustc/rust-analyzer
```

`cas` self-elevates via `sudo` if not already running as root, then
shells out to `cryptsetup`, `btrfs`, `udisksctl`, `losetup`, `blkid`,
`mount`/`umount`, and `udevadm` — all expected to already be on `PATH`.
The Nix package wraps the binary with all of them.

## Quick start

```sh
cas myvault create          # 1 GiB vault in the current directory
cas myvault open            # prompts for a passphrase, mounts ./myvault
...put files in myvault/...
cas myvault close
```

`cas help` prints the full action list; `cas help <action>` gives
per-action usage and examples.

## Docs

- `docs/architecture.md` — module map and the design decisions behind
  the rewrite (why no CLI-parsing crate, the stdin-secret pattern, the
  metadata-restoration guarantee).
- `docs/metadata-format.md` — the exact on-disk byte layout of the
  vault metadata trailer (shared with the Python original — no
  compatibility shim needed).
- `docs/cli.md` — structured flag/action reference.
- `docs/usage.md` — worked examples: first vault, 2FA on a USB drive,
  scripted use, routine snapshots.
- `docs/porting-notes.md` — what changed versus the original and why.
- `glossar/glossary.md` — LUKS/btrfs/udisks domain vocabulary used
  throughout the code and docs.

## Project layout

```
src/
  main.rs, cli.rs        entry point + argv dispatch
  config.rs, error.rs,   shared types (constants, CasError, Ctx)
  ctx.rs
  meta.rs, secret.rs,    vault-specific logic (metadata trailer,
  vault.rs               secret derivation, path resolution)
  luks.rs, btrfs.rs,     system-interaction wrappers (one module per
  udisks.rs,             external tool)
  keyfile_mount.rs, proc.rs
  size.rs, prompt.rs,    small focused utilities
  help.rs
  commands/              one file per action — see docs/architecture.md
    backup/                 for how to add a new one
docs/                   architecture, format, CLI, and usage docs
glossar/                domain glossary
```

## Status

Wired in via `Nixos/config/software/packages/{registry,packages}.nix`
(the same `custom` package pattern already used for `crun`/`ltree`),
packaged by `flake.nix`, and picked up by the root `flake.nix` as the
`casket` input. Requires a rebuild (`pacnix`/`nixos-rebuild switch`) to
take effect on `PATH`.

Tested against a disposable copy of a real production vault covering
every action (create, open/close/toggle, passwd, 2fa on/off, encryption
on/off, backup create/list/restore/delete/auto, resize grow/shrink,
rename, delete, list), with metadata round-tripped through both this
tool and the Python original to confirm the on-disk format is identical.
