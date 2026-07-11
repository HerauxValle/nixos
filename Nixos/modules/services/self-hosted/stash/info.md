# Stash -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./stash.nix`. Package fetch: `./package.nix`.
Real values: `Nixos/config/self-hosted/stash.nix`.

Binary comes from a pure Nix fetch (`package.nix`), same as Ollama -- no
venv, no FHS sandbox. Simplest service in the tree: one live unit, and an
action set that's mostly no-ops (nothing to install, nothing to sync) for
consistency with the other services -- see below.

## Options (`vars.selfHosted.stash`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | `true` | Master switch. |
| `dataDir` | str | `~/Images/SelfHosted/Stash` | Base dir; the real data location is `dataDir/<storage[0].src>` (config.yml, database, thumbnails, cache, blobs). |
| `autoStart` | bool | `true` | Same meaning as every other service here. |
| `host` | str | `"0.0.0.0"` | Passed as `--host` -- real typed option (not env passthrough) because `stash.nix` has to build a CLI command, not just export a var. |
| `port` | port | `9999` | Passed as `--port`. |
| `version` | str | *required* | Stash release version to pin. |
| `hash` | str | *required* | SRI sha256 of that version's `stash-linux` release asset. |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process. |
| `storage` | listOf `{src,dest}` | `[ ]` | Stash only ever has one real entry in practice -- `liveDataDir` in `stash.nix` is literally `dataDir/storage[0].src`, so the first entry is load-bearing. |
| `requireMounts` | listOf str | `[ ]` | Paths checked as mountpoints (`mountpoint -q`) before preStart runs -- e.g. the Casket vault `storage` points into. Plain data, not derived from `storage`. |

## systemd units

- `self-hosted-stash.service` -- the live process.
- `self-hosted-stash@install` -- no-op, prints a note (binary is a plain
  Nix store path, already there after rebuild).
- `self-hosted-stash@sync` -- no-op, prints a note (no declarative
  models/nodes for this service).
- `self-hosted-stash@uninstall` -- tier 1: removes anything directly
  under `dataDir` not covered by `storage`. In practice, nothing --
  Stash's entire footprint lives behind its one `storage` entry, so this
  is effectively also a no-op today.
- `self-hosted-stash@uninstall:data` -- tier 1, plus what `storage`
  actually points at: the real database/metadata/cache/blobs inside the
  vault. **Not recoverable.**
- `self-hosted-stash@update` -- checks `stashapp/stash`'s GitHub releases
  for something newer than `version`. **Print-only** -- never edits
  `config/self-hosted/stash.nix` itself. Read the new `version`/`hash`
  from `journalctl -u self-hosted-stash@update`, paste them in by hand,
  rebuild.
- `self-hosted-stash@update:apply` -- same check, but if something's
  newer, `sed`-writes the new `version`/`hash` straight into
  `config/self-hosted/stash.nix` instead of just printing them. Still
  doesn't rebuild or restart anything.

## Deliberately not ported

The old `runtime.sh`'s autotag/filemonitor GraphQL calls (source was
itself marked `Old/` -- legacy) and its Electron webapp auto-launch (a
systemd service has no display/session to launch a GUI into). If either
turns out to actually be wanted, it fits as a `mkActionService` action,
same shape as Ollama's `@sync`.

## Workflows

**Bump the Stash version**: `systemctl start self-hosted-stash@update:apply`
(writes directly), or `@update` first to see the diff before it lands.
Then rebuild, restart `self-hosted-stash.service`.

**Change bind host/port**: edit `host`/`port` in the same file, rebuild,
restart.

**Full teardown, including the real data**: `systemctl start
self-hosted-stash@uninstall:data`. This deletes the actual Stash
database/metadata/blobs inside the vault -- not just symlinks or
install artifacts. Think before running it.
