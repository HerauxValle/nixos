# OpenWebUI -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./openwebui.nix`. Implementation detail
pieces: `./lib/{fhs,update}.nix`.
Real values: `Nixos/config/self-hosted/openwebui.nix`.
Lockfile + source list: `Python/locks/self-hosted/openwebui/{requirements.lock,requirements.in}`.

Runs from a pip-installed venv inside a `buildFHSEnv` sandbox (compiled
wheels like pillow/lxml need a real `/lib`,`/usr/lib` that doesn't exist on
NixOS). The sandbox derivation itself is pure/reproducible; only what pip
installs inside it (via `preStart`'s `venvEnsureScript`, automatically on
every start) is the deliberately-impure part of this service. CPU-only --
talks to Ollama over its API for actual inference, no GPU access needed
here. No manual install step, no manual sync/uninstall action -- the only
action left is `update`/`update:apply`, see below.

## Options (`vars.selfHosted.openwebui`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service + actions exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" below), not just absent. |
| `dataDir` | str | `~/Applications/Networking/OpenWebUI` | Plain, always-available. Real data is at `dataDir/<storage[0].src>` (`liveDataDir`), which also sets `DATA_DIR` for the process. |
| `venvDir` | str | `~/.impure/python-venvs/self-hosted/openwebui` | Disposable, fully regenerated from `requirements.lock` automatically by preStart's `venvEnsureScript` whenever the lock's hash changes. Lives under `~/.impure/` deliberately -- see that directory's own reasoning below. |
| `autoStart` | bool | `true` | Currently `false` in this machine's real config. |
| `host` | str | `"0.0.0.0"` | Passed as `--host`. |
| `port` | port | `8080` | Passed as `--port`. |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process. |
| `storage` | listOf `{src,dest}` | `[ ]` | First entry is the real data location, same convention as Stash. |
| `requireMounts` | listOf str | `[ ]` | Mountpoint checks before preStart, e.g. the vault `storage` points into. |
| `teardownPaths` | listOf str | `[ ]` | Paths, relative to `dataDir`, removed when `enabled = false`. Empty here (the safe default) since `dataDir` holds nothing but the `storage` symlink itself -- "everything but storage" is correct as-is. See `../docs/architecture.md`'s `mkTeardownActivationScript` section. |

## systemd units

- `self-hosted-openwebui.service` -- the live process, runs inside the FHS
  sandbox. `preStart` runs `venvEnsureScript` on every start (no-op unless
  `requirements.lock`'s hash changed) before generating the secret key and
  starting the process. `TimeoutStartSec=infinity` -- a first-time (or
  post-lock-change) venv install can legitimately take much longer than
  systemd's default 90s start timeout; see ComfyUI's `info.md` for the
  real incident this was found from.
- `self-hosted-openwebui@update` -- re-runs pip-compile against
  `requirements.in`, diffs against the checked-in `requirements.lock`.
  **Print/diff-only** -- never overwrites the real lock. If it differs,
  leaves the new one at `requirements.lock.new` and prints a
  package/version diff via `journalctl -u self-hosted-openwebui@update`.
- `self-hosted-openwebui@update:apply` -- same check, but if it differs,
  moves the new lock straight into place instead of leaving `.new` for
  you to `mv` yourself. Still doesn't rebuild or restart anything --
  those stay separate, deliberate steps. No follow-up install action
  needed either: the next restart's preStart picks up the new hash
  automatically.

## `WEBUI_SECRET_KEY`

Generated once into `<liveDataDir>/.webui_secret_key` (32 random bytes,
base64) by `preStart` if it doesn't already exist, then read into the
environment at every start. Lives with the real data (survives a venv
reinstall), not in the Nix store.

## Known: `alembic_version` predates this codebase's migration chain

`webui.db` (the real, pre-Nix vault data) has been through multiple
OpenWebUI schema-storage generations over its lifetime -- a Peewee-era
`migratehistory` table (pre-Alembic), then an Alembic `alembic_version`
table stamped `42e2978c7933`, a revision ID that this version's (`0.9.6`)
own migration chain doesn't recognize at all (squashed/renamed upstream at
some point between then and now). `run_migrations()` catches this
(`alembic.util.exc.CommandError: Can't locate revision`) and logs it as an
error but doesn't crash the app -- confirmed real user data (chats, users,
config) all read back correctly regardless. The practical effect: any
*future* Alembic migration this version might need won't apply
automatically until this is resolved (likely `alembic stamp <head>` once
the actual schema is verified column-by-column to already match head --
not done here, deliberately not guessed at blind). If a future `@update`
starts throwing real (not just this cosmetic) errors, this is the first
thing to check.

A related, already-fixed instance of the same underlying problem: the
`config` table itself was still on the *very* old key/value-per-row
schema (a table that predates Alembic requiring `id`/`data`/`version`) --
the `ca81bd47c050` migration only creates `config` `if not exists`, so it
silently no-opped against this database, and the app crashed on startup
(`OperationalError: no such column: config.id`) the first time this
version was pointed at the real vault data. Fixed by hand -- converted the
382 flat key/value rows (the real, last-updated-Jun-29 settings) into the
nested JSON blob shape `ConfigTable`/`ConfigState` (`internal/config.py`)
expects, as a new `config` table; both the old flat table and an
already-stale, abandoned Apr-12 migration attempt (`config_old`, 1 row)
were renamed aside as `config_legacy_kv_20260629` /
`config_migrated_20260412_backup` rather than dropped. Confirmed after:
service `active (running)`, 0 restarts, `/health` OK, `/api/config`
reflecting the migrated settings, real user/chat counts intact via direct
DB query.

## Updating packages

`requirements.in` (`Python/locks/self-hosted/openwebui/requirements.in`) is
a small, static, hand-maintained file -- unlike ComfyUI's, nothing here
depends on Nix-fetched sources, so there's no generation step. `open-webui`
itself is listed unpinned, so `@update` alone already picks up newer
releases without editing anything.

1. `systemctl start self-hosted-openwebui@update:apply` -- writes the new
   lock directly if anything's newer. Or `@update` first (no target) if
   you want to review the `requirements.lock.new` diff before it lands.
2. To bump something specific (not just "whatever's newest"), edit
   `requirements.in` first, then run `@update`/`@update:apply` the same
   way.
3. Rebuild, restart `self-hosted-openwebui.service` -- preStart's
   `venvEnsureScript` picks up the new lock hash and reinstalls
   automatically, no separate step needed.

## Full teardown

Set `enabled = false` in `config/self-hosted/openwebui.nix`, rebuild --
`mkTeardownActivationScript` (`../self-hosted.nix`) removes `venvDir` and
everything under `dataDir` not covered by `storage` automatically, as
part of that same rebuild's activation. The actual chat/user data inside
the vault (the `storage` entry) is never touched by this -- only a
deliberate, by-hand `rm -rf` removes that. Flip `enabled` back to `true`
and rebuild again to reinstall.

## `~/.impure/`

`venvDir` deliberately lives outside `dataDir`, under
`~/.impure/python-venvs/self-hosted/<name>/`. A venv is exactly what that
directory exists to hold: real files on disk that Nix did not create and
cannot fully account for (pip-installed packages, not derivations),
structurally separated from `dataDir`'s declared/backed-up data so nothing
ever conflates the two.
