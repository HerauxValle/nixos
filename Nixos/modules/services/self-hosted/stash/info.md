# Stash -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./stash.nix`. Implementation detail
pieces: `./lib/{package,update}.nix`.
Real values: `Nixos/config/self-hosted/stash.nix`.

Binary comes from a pure Nix fetch (`lib/package.nix`), same as Ollama --
no venv, no FHS sandbox. Simplest service in the tree: one live unit, no
reconciliation logic at all (no declarative models/nodes), and the only
action is `update`/`update:apply` -- see below.

## Options (`vars.selfHosted.stash`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service + actions exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" below), not just absent. |
| `dataDir` | str | `~/Images/SelfHosted/Stash` | Base dir; the real data location is `dataDir/<storage[0].src>` (config.yml, database, thumbnails, cache, blobs). |
| `autoStart` | bool | `true` | Same meaning as every other service here. Currently `false` in this machine's real config. |
| `host` | str | `"0.0.0.0"` | Passed as `--host` -- real typed option (not env passthrough) because `stash.nix` has to build a CLI command, not just export a var. |
| `port` | port | `9999` | Passed as `--port`. |
| `version` | str | *required* | Stash release version to pin. |
| `hash` | str | *required* | SRI sha256 of that version's `stash-linux` release asset. |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process. |
| `storage` | listOf `{src,dest}` | `[ ]` | Stash only ever has one real entry in practice -- `liveDataDir` in `stash.nix` is literally `dataDir/storage[0].src`, so the first entry is load-bearing. |
| `requireMounts` | listOf str | `[ ]` | Paths checked as mountpoints (`mountpoint -q`) before preStart runs -- e.g. the Casket vault `storage` points into. Plain data, not derived from `storage`. |
| `teardownPaths` | listOf str | `[ ]` | Paths, relative to `dataDir`, removed when `enabled = false`. Empty here (the safe default) since `dataDir` holds nothing but the `storage` symlink itself -- "everything but storage" is correct as-is. See `../docs/architecture.md`'s `mkTeardownActivationScript` section. |

## systemd units

- `self-hosted-stash.service` -- the live process. `preStart` just
  `mkdir -p`s Stash's own subdirectories (`plugins`, `scrapers`,
  `metadata`, `cache`, `generated`, `blobs`) under the live data dir --
  no reconciliation, nothing to install. `TimeoutStartSec=infinity`, same
  as every service here -- see ComfyUI's `info.md` for the real incident
  this was found from (not that Stash itself has a slow install; the fix
  is generic, applied to all four services regardless).
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
same shape as the `update` actions already here.

## Workflows

**Bump the Stash version**: `systemctl start self-hosted-stash@update:apply`
(writes directly), or `@update` first to see the diff before it lands.
Then rebuild, restart `self-hosted-stash.service`.

**Change bind host/port**: edit `host`/`port` in the same file, rebuild,
restart.

**Full teardown**: set `enabled = false` in `config/self-hosted/stash.nix`,
rebuild -- `mkTeardownActivationScript` (`../self-hosted.nix`) removes
everything under `dataDir` not covered by `storage` automatically, as
part of that same rebuild's activation. The actual Stash
database/metadata/blobs inside the vault (the `storage` entry) are never
touched by this -- only a deliberate, by-hand `rm -rf` removes those.
Flip `enabled` back to `true` and rebuild again to reinstall.
