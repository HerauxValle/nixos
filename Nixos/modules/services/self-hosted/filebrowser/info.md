# FileBrowser -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./filebrowser.nix`. Implementation
detail pieces: `./lib/{package,update}.nix`.
Real values: `Nixos/config/self-hosted/filebrowser.nix`.

Binary comes from a pure Nix fetch (`lib/package.nix`), same as
Ollama/Stash -- no venv, no FHS sandbox. Simplest service in the tree:
one live unit, a single BoltDB file (not sqlite -- confirmed by
inspecting the file's magic bytes, `0xED0CDAED`), no reconciliation
logic at all, and the only action is `update`/`update:apply`.

Ported from `~/Scripts/Self-hosted/FileBrowser/`, read as a behavioral
reference only. nixpkgs also packages `filebrowser` directly, but this
pins its own release the same way every other service here does, rather
than being the one exception tied to nixpkgs' own update schedule.

## Options (`vars.selfHosted.filebrowser`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service + actions exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" below), not just absent. |
| `dataDir` | str | `~/Applications/Networking/FileBrowser` | Plain base dir; the real data location is `dataDir/<storage[0].src>` (the BoltDB -- users, settings, everything `config set`/the UI changes). |
| `autoStart` | bool | `true` | Same meaning as every other service here. |
| `host` | str | `"127.0.0.1"` | Passed as `--address` on every start, and baked into the BoltDB via `config set` the first time it's created. |
| `port` | port | `8090` | Passed as `--port`, same two-places-it-lands as `host`. |
| `root` | str | `homeDirectory` | Filesystem root FileBrowser serves, applied once via `config init --root` when the BoltDB doesn't exist yet. Ported faithfully from the original `FB_ROOT="$HOME"` -- the old setup deliberately browsed the whole home directory, not a scoped-down subset. Changing this after the database already exists has no effect on its own (`filebrowser config set --root ...` by hand would be needed). |
| `version` | str | *required* | FileBrowser release version to pin. |
| `hash` | str | *required* | SRI sha256 of that version's `linux-amd64-filebrowser.tar.gz` release asset. |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process. |
| `storage` | listOf `{src,dest}` | `[ ]` | One real entry in practice -- `liveDataDir` in `filebrowser.nix` is literally `dataDir/storage[0].src`, so the first entry is load-bearing. |
| `requireMounts` | listOf str | `[ ]` | Paths checked as mountpoints (`mountpoint -q`) before preStart runs -- e.g. the Casket vault `storage` points into. Plain data, not derived from `storage`. |
| `teardownPaths` | listOf str | `[ ]` | Paths, relative to `dataDir`, removed when `enabled = false`. Empty here (the safe default) since `dataDir` holds nothing but the `storage` symlink itself. |

## systemd units

- `self-hosted-filebrowser.service` -- the live process. `preStart`
  bootstraps the BoltDB (`filebrowser config init -r <root>` then
  `config set -a <host> -p <port>`) **only if `dbFile` doesn't already
  exist** -- faithful port of the old `install.sh`'s
  `[[ ! -f "$FB_DB" ]]` guard. A pre-existing/recovered `filebrowser.db`
  placed at the real storage path is picked up as-is, same as every
  other service's preStart reconciliation deferring to real existing
  data. `TimeoutStartSec=infinity`, same as every service here (a
  first-time GitHub-release fetch is the only thing that could
  legitimately take a while -- this service otherwise starts instantly).
- `self-hosted-filebrowser@update` -- checks `filebrowser/filebrowser`'s
  GitHub releases for something newer than `version`. **Print-only** --
  never edits `config/self-hosted/filebrowser.nix` itself. Read the new
  `version`/`hash` from `journalctl -u self-hosted-filebrowser@update`,
  paste them in by hand, rebuild.
- `self-hosted-filebrowser@update:apply` -- same check, but if something's
  newer, `sed`-writes the new `version`/`hash` straight into
  `config/self-hosted/filebrowser.nix` instead of just printing them.
  Still doesn't rebuild or restart anything.

## Real, migrated data

This machine had a real `filebrowser.db` (BoltDB) from before the Nix
port, recovered from a backup snapshot at
`/run/media/<user>/Media/Home/.config/filebrowser/filebrowser.db`
(the old bash framework's `FB_BASE="$HOME/.config/filebrowser"`, never
vault-backed in the original setup). Copied into
`~/Images/SelfHosted/FileBrowser/filebrowser.db` -- the vault-backed
`storage` destination this module actually uses -- so the real
users/settings from before carry forward instead of a fresh
`config init` silently generating a new default admin user. Whatever
host/address/root were actually baked into that recovered database at
the time win over this module's own `host`/`port`/`root` defaults
(preStart's init-guard never touches an existing database), same as
every other service's "existing real data wins" convention.

## Deliberately not ported

FileBrowser's own `main.sh --logs`/`--debug-logs` distinction doesn't
apply here -- `journalctl -u self-hosted-filebrowser` covers both (no
separate always-on debug log file the old nohup-based runtime.sh needed).

## Workflows

**Bump the FileBrowser version**:
`systemctl start self-hosted-filebrowser@update:apply` (writes directly),
or `@update` first to see the diff before it lands. Then rebuild, restart
`self-hosted-filebrowser.service`.

**Change bind host/port**: edit `host`/`port` in the same file, rebuild,
restart -- these are re-applied via `-a`/`-p` on every start regardless
of what's already in the BoltDB (unlike `root`, which is init-only).

**Full teardown**: set `enabled = false` in
`config/self-hosted/filebrowser.nix`, rebuild --
`mkTeardownActivationScript` (`../self-hosted.nix`) removes everything
under `dataDir` not covered by `storage` automatically, as part of that
same rebuild's activation. The actual BoltDB inside the vault (the
`storage` entry) is never touched by this -- only a deliberate, by-hand
`rm -rf` removes it. Flip `enabled` back to `true` and rebuild again to
reinstall (a fresh `config init` only fires if the BoltDB is actually
gone).
