# OpenWebUI -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./openwebui.nix`. FHS sandbox: `./fhs.nix`.
Real values: `Nixos/config/self-hosted/openwebui.nix`.
Lockfile + source list: `Python/locks/self-hosted/openwebui/{requirements.lock,requirements.in}`.

Runs from a pip-installed venv inside a `buildFHSEnv` sandbox (compiled
wheels like pillow/lxml need a real `/lib`,`/usr/lib` that doesn't exist on
NixOS). The sandbox derivation itself is pure/reproducible; only what pip
installs inside it (via `@install`) is the deliberately-impure part of this
service. CPU-only -- talks to Ollama over its API for actual inference, no
GPU access needed here.

## Options (`vars.selfHosted.openwebui`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | `true` | Master switch. |
| `dataDir` | str | `~/Applications/Networking/OpenWebUI` | Plain, always-available. Real data is at `dataDir/<storage[0].src>` (`liveDataDir`), which also sets `DATA_DIR` for the process. |
| `venvDir` | str | `~/.impure/python-venvs/self-hosted/openwebui` | Disposable, fully regenerable from `requirements.lock` via `@install`. Lives under `~/.impure/` deliberately -- see that directory's own reasoning below. |
| `autoStart` | bool | `true` | |
| `host` | str | `"0.0.0.0"` | Passed as `--host`. |
| `port` | port | `8080` | Passed as `--port`. |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process. |
| `storage` | listOf `{src,dest}` | `[ ]` | First entry is the real data location, same convention as Stash. |
| `requireMounts` | listOf str | `[ ]` | Mountpoint checks before preStart, e.g. the vault `storage` points into. |

## systemd units

- `self-hosted-openwebui.service` -- the live process, runs inside the FHS sandbox.
- `self-hosted-openwebui@install` -- wipes and recreates `venvDir`,
  `pip install --require-hashes -r requirements.lock`.
- `self-hosted-openwebui@sync` -- no-op, prints a note (no declarative
  models/nodes for this service).
- `self-hosted-openwebui@uninstall` -- removes `venvDir`, plus anything
  directly under `dataDir` not covered by `storage`. Recoverable: `@install`
  rebuilds the venv.
- `self-hosted-openwebui@uninstall:data` -- tier 1, plus what `storage`
  actually points at: the real chat/user data inside the vault. **Not
  recoverable.**
- `self-hosted-openwebui@update` -- re-runs pip-compile against
  `requirements.in`, diffs against the checked-in `requirements.lock`.
  **Print/diff-only** -- never overwrites the real lock. If it differs,
  leaves the new one at `requirements.lock.new` and prints a
  package/version diff via `journalctl -u self-hosted-openwebui@update`.
- `self-hosted-openwebui@update:apply` -- same check, but if it differs,
  moves the new lock straight into place instead of leaving `.new` for
  you to `mv` yourself. Still doesn't rebuild, restart, or run `@install`
  -- those stay separate.

## `WEBUI_SECRET_KEY`

Generated once into `<liveDataDir>/.webui_secret_key` (32 random bytes,
base64) by `preStart` if it doesn't already exist, then read into the
environment at every start. Lives with the real data (survives a venv
reinstall), not in the Nix store.

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
3. Rebuild, restart `self-hosted-openwebui.service`, then
   `systemctl start self-hosted-openwebui@install`.

## Full teardown, including the real data

`systemctl start self-hosted-openwebui@uninstall:data` -- deletes the
actual chat/user data inside the vault, not just the venv. Think before
running it.

## `~/.impure/`

`venvDir` deliberately lives outside `dataDir`, under
`~/.impure/python-venvs/self-hosted/<name>/`. A venv is exactly what that
directory exists to hold: real files on disk that Nix did not create and
cannot fully account for (pip-installed packages, not derivations),
structurally separated from `dataDir`'s declared/backed-up data so nothing
ever conflates the two.
