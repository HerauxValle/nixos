<!-- &desc: "Odysseus service reference -- uvicorn AI workspace app (chat, agents, research, docs, memory), git-cloned+pinned to coreRev, data symlinked into srcDir." -->

# Odysseus -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./odysseus.nix`. Implementation detail
pieces: `./lib/{fhs,update}.nix`. Real values:
`Nixos/config/self-hosted/odysseus.nix`.

Real upstream project: [github.com/pewdiepie-archdaemon/odysseus](https://github.com/pewdiepie-archdaemon/odysseus)
(confirmed via `git remote -v` against the real checkout already
recovered in the vault, not guessed) -- a self-hosted AI workspace
(chat, agents, deep research, documents, memory/skills, email,
notes/tasks, calendar). FastAPI + uvicorn, git-clone-pinned source (no
pip package -- confirmed, no `build-system` in `pyproject.toml`, just
pytest config), same shape as SearXNG, not OpenWebUI.

## Why this looks like SearXNG, not OpenWebUI

Every other venv-based service either installs a real pip package
(OpenWebUI) or has no meaningful data of its own beyond a settings file
(SearXNG). Odysseus is closer to SearXNG mechanically (a plain writable
git checkout, pinned to `coreRev`, re-checked-out every start) but with
one real difference that shapes this whole module: Odysseus's own
application code (`setup.py`, `core/database.py`, `load_dotenv()`)
computes its data paths (`data/`, `.env`) as plain subdirectories/files
relative to wherever the running script itself lives -- there is no
env-var override for this the way SearXNG's `SEARXNG_SETTINGS_PATH`
lets Nix point `settings.yml` wherever it wants. Confirmed by reading
`setup.py` directly (`BASE_DIR = os.path.dirname(os.path.abspath(__file__))`,
`DATA_DIR = os.path.join(BASE_DIR, "data")`) and `app.py`
(`load_dotenv()` with no path argument, searches from cwd).

Consequence: this module has **no `dataDir` at all** (only Immich
shares that shape, for a completely unrelated reason -- see its own
`default.nix`). The real vault-backed data gets symlinked *directly
into* `srcDir` by `odysseus.nix`'s own `dataLinkScript`, not through the
generic dataDir-anchored `L+` tmpfiles mechanism every other
storage-having service uses (that mechanism hard-interpolates
`${dataDir}` whenever `storage` is non-empty -- confirmed by reading
`mk-self-hosted-service.nix` directly, which would crash outright with
`dataDir = null`). `dataLinkScript` mirrors SearXNG's own
`themeLinkScript` exactly: `rm -rf` the destination first, then
`ln -sfn` -- a fresh git clone can ship its own placeholder paths (or
none at all), and a bare `ln -sfn` can't force-replace a real directory.

## Options (`vars.selfHosted.odysseus`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service + actions exist and run. `false` = only `venvDir` gets torn down on the next rebuild -- `srcDir` doesn't (same already-accepted limitation as SearXNG's own `srcDir`), and storage-backed real data is never touched either way. |
| `venvDir` | str | `~/.impure/python-venvs/self-hosted/odysseus` | Disposable, regenerated from `requirementsLock` automatically whenever its hash changes. |
| `srcDir` | str | `~/.impure/python-venvs/self-hosted/odysseus-src` | A **fresh** git clone, pinned to `coreRev` -- deliberately not reusing the checkout already sitting in the vault (`~/Images/SelfHosted/Odysseus`), which stays real/vault-backed/storage-only from Nix's perspective. |
| `autoStart` | bool | `true` | Same meaning as every other service. Currently `false` in this machine's real config. |
| `host` | str | `"0.0.0.0"` | Passed as uvicorn's `--host` -- always explicit, no "leave as-is" mechanism the way SearXNG's `settings.yml` provides. Matches the real value the old `main.sh` already used. |
| `port` | port | `7000` | Passed as uvicorn's `--port`. Matches upstream's own real default and the old `main.sh`'s value. |
| `environment` | attrsOf str | `{ }` | Passthrough, layered on top of whatever the real `.env` (see `storage`) already sets via the app's own `load_dotenv()` call -- most config already lives there, this is only for overrides. |
| `storage` | listOf `{src,dest}` | `[ ]` | Symlinked directly into `srcDir` by `dataLinkScript`, **not** dataDir-anchored (see above). Real value: `data`, `logs`, `.env`, each pointing into the vault. |
| `requireMounts` | listOf str | `[ ]` | Checked before `preStart` runs. Real value: the SelfHosted vault's own mountpoint. |
| `coreRev` | str | *required* | Git rev to pin, re-checked-out every start (no-op once already there). Real value is the exact commit the vault's already-recovered checkout was sitting at, not just "whatever HEAD is upstream today". |

## Real, recovered data -- an already-working install, not a fresh one

Unlike Immich's fresh-database situation, `~/Images/SelfHosted/Odysseus/`
(89MB) is a **genuinely already-working** prior install: `data/auth.json`
(a real admin account, bcrypt-hashed), `data/app.db` (a real SQLite
database with actual content), `data/settings.json`, `data/sessions.json`,
`data/presets.json`, `data/skills/`, `data/memory.json`, plus real
generated content (`uploads/`, `personal_docs/`, `generated_images/`,
`chroma/`, `rag/`, etc.). Confirmed by inspecting the directory directly,
not assumed. The old `venv/` there is dead (`pyvenv.cfg` points at
`/usr/bin/python3.14`, which doesn't exist on this NixOS install) -- a
completely fresh venv gets built under `~/.impure/` instead, same as
every other venv-based service; nothing about the dead old venv matters
once `srcDir`/`venvDir` are wired up independently.

`setup.py` (upstream's own idempotent first-run script, "safe to re-run
(skips what already exists)") still runs every `preStart`, **after**
`dataLinkScript` -- confirmed safe by reading it directly: it only
creates `data/auth.json` if that file doesn't already exist, and it
does, so this is a genuine no-op on this machine, not a fresh bootstrap.
`ODYSSEUS_SKIP_ADMIN_PROMPT=1` is set defensively when running it, even
though `setup.py` already detects a non-interactive stdin (never a real
TTY under systemd) and would skip prompting on its own.

## Python 3.14, not 3.12 like every other venv-based service

Confirmed via the dead old venv's own `pyvenv.cfg` (`version = 3.14.5`,
`executable = /usr/bin/python3.14`) -- the real, already-working prior
install actually ran on 3.14, and Odysseus's own README states only
"Python 3.11+" with no upper bound, so there's no reason to downgrade
from what was last confirmed working. Verified for real this session
(not assumed): a full `pip install --require-hashes -r requirements.lock`
inside the real FHS sandbox succeeded cleanly on `python314`, and every
compiled extension (`bcrypt`, `cryptography`, `lxml`, `numpy`, `pillow`,
`grpcio`, `onnxruntime`, `fastembed`) actually *imports* too, not just
installs -- run standalone before wiring the full module, matching this
framework's own "verify against the real thing" standard.

## systemd units

- `self-hosted-odysseus.service` -- the live process. `preStart`, in
  order: (1) ensure `venvDir`/`srcDir`'s parent dirs exist, (2)
  `srcEnsureScript` (clone/checkout `coreRev`, no-op if already there),
  (3) `venvEnsureScript` (hash-locked venv install, no-op unless the
  lock changed), (4) `dataLinkScript` (symlink real data into `srcDir`),
  (5) `setupScript` (`python setup.py`, a genuine no-op on this
  machine's real data). `execStart` runs inside the FHS sandbox, `cd
  srcDir` first (matching upstream's own `odysseus-ui.service` template
  exactly: `WorkingDirectory=.../odysseus-ui`,
  `ExecStart=.../uvicorn app:app --port ... --host ...`) -- uvicorn
  resolves `app:app` relative to cwd, no `.pth` trick needed (unlike
  SearXNG's `import searx`).
- `self-hosted-odysseus@update` / `@update:apply` /
  `@update:core[:apply]` / `@update:deps[:apply]` -- identical shape to
  SearXNG's own action family: `update:core` checks
  `pewdiepie-archdaemon/odysseus`'s default branch HEAD against
  `coreRev`, `update:deps` re-runs `pip-compile` and diffs against the
  checked-in lock. `update` (bare) does both. Print-only by default,
  `:apply` writes (`coreRev` sed'd into `config/self-hosted/odysseus.nix`,
  or the new lock moved into place) -- never rebuilds or restarts.

## Not yet done

Written and verified at the FHS/venv-install level this session, but
**not yet dry-built as a full module, not yet started for real**. Do
both before considering this actually done, per this framework's own
"verify before calling it done" standard -- especially a real
`systemctl start self-hosted-odysseus` and a real `curl` against the
live port, plus reading the generated `srcEnsureScript`/`dataLinkScript`/
`setupScript` content directly (`nix build` the relevant
`unit-script-*` derivations, same technique used for Immich's own
`immich-server-pre-start`).
