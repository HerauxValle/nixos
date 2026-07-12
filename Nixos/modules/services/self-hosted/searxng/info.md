# SearXNG -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./searxng.nix`. Implementation detail
pieces: `./lib/{fhs,update}.nix`.
Real values: `Nixos/config/self-hosted/searxng.nix`.
Lockfile + source list: `Python/locks/self-hosted/searxng/{requirements.lock,requirements.in}`.
Real theme sources: `Dotfiles/Themes/Searxng/{simple,adversarial}/` -- same
top-level convention as every other themed app in this repo (Kvantum,
QT, Dolphin, Gwenview, GRUB), not under `Nixos/config/`.

Runs from a git-checked-out source (`srcDir`) plus a pip-installed venv,
both inside a `buildFHSEnv` sandbox (lxml needs a real `/lib`,`/usr/lib`
that doesn't exist on NixOS). SearXNG has no pip package at all --
confirmed in the old bash framework's own `toolchain.sh` comment,
"SearXNG has no pip package -- installed from git" -- so unlike
OpenWebUI/ComfyUI's core, `srcDir` is a plain writable git clone pinned
to `coreRev`, not a `fetchFromGitHub` store path. That's a deliberate
difference: ComfyUI's core needs to be an immutable store path because
`custom_nodes/` needs a real bind-mount trick to stay writable per node;
SearXNG has no such requirement -- the only thing that needs to write
into the checkout is the theme symlinks (see below), which a plain
writable clone handles directly, no sandbox trickery needed -- though
not with a *bare* `ln -sfn`, see "systemd units" below for why.

## Options (`vars.selfHosted.searxng`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. `true` = live service + actions exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" below), not just absent. |
| `dataDir` | str | `~/Applications/Networking/SearXNG` | Plain base dir -- holds only the `settings.yml` symlink (see `storage`). |
| `venvDir` | str | `~/.impure/python-venvs/self-hosted/searxng` | Disposable, regenerated from `requirementsLock` automatically by `preStart`'s `venvEnsureScript` whenever the lock's hash changes. |
| `srcDir` | str | `~/.impure/python-venvs/self-hosted/searxng-src` | The `searxng/searxng` git checkout, pinned to `coreRev` every start (no-op if already there). A sibling of `venvDir`, not nested inside it -- `venvDir` gets fully wiped on every lock-hash change, which would force a needless re-clone if `srcDir` lived inside it. |
| `autoStart` | bool | `true` | Same meaning as every other service here. Currently `false` in this machine's real config. |
| `coreRev` | str | *required* | `searxng/searxng` git rev to pin. No `coreHash` alongside it -- see this file's top section for why. |
| `secret` | str | *required* | Exported as `SEARXNG_SECRET` on every start. SearXNG's own `settings_defaults.py` (`SettingsValue(environ_name="SEARXNG_SECRET")`) reads this and unconditionally overrides settings.yml's `server.secret_key` with it -- confirmed by reading that file directly, not assumed from the settings.yml comment (which describes the Docker image's separate `envsubst` mechanism, not something SearXNG's own Python does). |
| `environment` | attrsOf str | `{ }` | Passthrough env for the live process. |
| `storage` | listOf `{src,dest}` | `[ ]` | One real entry: `settings.yml` (a **single file**, not a directory -- `L+` tmpfiles symlinks don't care which) -> the real, hand-customized settings.yml in the vault. |
| `requireMounts` | listOf str | `[ ]` | Paths checked as mountpoints before `preStart` runs -- the Casket vault `storage` points into. |
| `teardownPaths` | listOf str | `[ ]` | Paths, relative to `dataDir`, removed when `enabled = false`. Empty here (the safe default) -- `dataDir` holds nothing but the `settings.yml` symlink itself. |
| `themes` | listOf `{name,path}` | `[ ]` | Real theme sources, symlinked into the live checkout's `searx/templates/<name>` and `searx/static/themes/<name>` by `preStart`, same mechanism as the old `links.sh`. Not a store/installed split like ComfyUI's nodes -- every declared theme always gets linked, there's no "declared but not wanted" catalog problem here. |

## `settings.yml` -- deliberately outside Nix's reach (mostly)

Unlike every other option here, there is **no** typed `host`/`port`/
`theme` option for SearXNG. The real settings.yml (instance name,
plugins, ~15 individually toggled search engines, `ui.default_theme`,
`server.bind_address`/`port`) is real, hand-customized data that already
lives in the vault (`storage`'s one entry) -- Nix's job is making sure
that symlink exists, nothing more. Changing any of those values means
editing the real file directly (or, for the theme specifically, see
below) -- exactly the same relationship Nix has with Stash's `config.yml`.

**The one exception is `secret`** (see the options table) -- SearXNG
hard-refuses to start with the literal placeholder
`server.secret_key: "ultrasecretkey"` still in effect
(`searx/webapp.py`: `if get_setting("server.secret_key") == 'ultrasecretkey':
logger.error(...)`, confirmed by reading that file directly on a real
failed start). The real vault settings.yml's `secret_key` value was
fixed from that placeholder to the same value the old bash framework's
`launch.sh` hardcoded (`314159265314159265`) -- not a fresh random value
-- as a fallback only; `SEARXNG_SECRET` (this option) always wins over
it at runtime regardless, per `settings_defaults.py`'s `SettingsValue`.

**Theme selection**: SearXNG has a **native** per-session theme switcher
(`/preferences` -> Interface -> Theme, cookie-based, no restart needed)
-- `ui.default_theme` in the real settings.yml is only the server-wide
fallback for anonymous/new visitors, currently `simple`. Both `simple`
and `adversarial` (a genuinely hand-crafted dark theme -- Playfair
Display/JetBrains Mono, red-on-paper palette) get symlinked in via
`themes` regardless of which one is the default, so both are always
selectable. There's deliberately no Nix-level `theme` option -- SearXNG
already supports this natively, adding one would just be duplicating a
feature that already exists.

## systemd units

- `self-hosted-searxng.service` -- the live process. `preStart`, in
  order: (1) `mkdir -p` `venvDir`/`srcDir`'s shared parent, (2)
  `srcEnsureScript` -- clone `srcDir` if missing, `git fetch` + checkout
  `coreRev` if the current checkout is at a different rev (no-op
  otherwise), (3) `venvEnsureScript` -- hash-locked pip install, skipped
  unless `requirementsLock`'s hash changed, with an `extraSteps` write of
  a `searxng.pth` file into the venv's site-packages pointing at
  `srcDir` (faithful port of the old install.sh's identical trick, since
  there's no real `pip install .` happening -- `import searx` resolves
  via this `.pth` file instead), (4) `themeLinkScript` -- `rm -rf` then
  `ln -sfn` every declared theme's `templates`/`static` into the
  checkout, every start. The `rm -rf` isn't cosmetic: SearXNG's own git
  source already ships a real (non-symlink) `searx/templates/simple/`
  directory, and a bare `ln -sfn` can't force-replace an existing real
  directory (only an existing symlink) -- confirmed on a real run, where
  this silently left the stock upstream `simple` theme in effect instead
  of the genuinely hand-edited one (`results.html`, `preferences.html`,
  etc. all differ from stock, confirmed by diff) until the `rm -rf` was
  added. `adversarial` never hit this because no stock theme exists at
  that path to collide with. Safe to `rm -rf` unconditionally -- `srcDir`
  is a disposable, regenerable checkout, never real user data. `execStart` runs
  `searx/webapp.py` directly from `srcDir` (matching the old
  `runtime.sh`, not the `searxng-run` console-script entry point that
  was never actually used), inside the FHS sandbox (lxml needs the real
  `/lib`,`/usr/lib` on every import, not just at install time).
  `TimeoutStartSec=infinity`, same as every service here.
- `self-hosted-searxng@update` -- checks `searxng/searxng`'s git HEAD
  against `coreRev`, then re-runs `pip-compile` against
  `requirements.lock`. **Print-only**.
- `self-hosted-searxng@update:core` / `@update:core:apply` -- just the
  core rev check/apply.
- `self-hosted-searxng@update:deps` / `@update:deps:apply` -- just the
  dependency lock check/apply.

## Real, migrated data

Two things existed pre-Nix but were never actually vault-backed:

- **`settings.yml`** -- was at
  `~/Scripts/Self-hosted/SearXNG/configuration/settings/settings.yml`
  (a dotfiles-tree path, `links.sh` symlinked it into the install dir at
  runtime). Copied by hand into
  `~/Images/SelfHosted/SearXNG/settings.yml` before the first rebuild --
  real instance data now lives vault-protected like every other
  service's precious data, instead of sitting in a script tree with no
  backup story of its own. Its `secret_key` value was also fixed from
  the non-functional placeholder `"ultrasecretkey"` to a real value --
  see the `settings.yml` section above.
- **Themes** (`simple`, `adversarial`) -- real, hand-crafted CSS/
  templates, genuinely code-like assets (not per-instance data), so they
  live at `Dotfiles/Themes/Searxng/` and are tracked in git there, same
  convention as every other themed app in this repo -- not under
  `Nixos/config/` (moved there after an initial pass mistakenly put them
  in `config/self-hosted/searxng/themes/`, corrected once pointed out).

The `data|.../SelfHosted/SearXNG/data` entry the old `storage.sh`
declared was **not** ported -- grepped the entire old bash tree and
found nothing that ever actually read from or wrote to it (no valkey/
redis is configured -- `settings.yml`'s `valkey.url` is `false`), and it
never existed on disk anywhere (checked both the live machine and the
backup drive). A declared-but-unused storage entry from the old
framework, not real behavior to preserve.

## Workflows

**Bump the core revision**:
`systemctl start self-hosted-searxng@update:core:apply` (writes directly
to `coreRev`), or `@update:core` first to see the diff. Then rebuild,
restart -- `srcEnsureScript` picks up the new rev automatically.

**Bump dependencies**: same shape, `@update:deps`/`@update:deps:apply`.

**Add another theme**: drop a new `templates/`+`static/` pair under
`Dotfiles/Themes/Searxng/<name>/`, add
`{ name = "<name>"; path = ../../../Themes/Searxng/<name>; }` to `themes`
in `config/self-hosted/searxng.nix`, rebuild, restart. Set it as the
server-wide default by editing the real vault `settings.yml`'s
`ui.default_theme` directly, or just pick it per-session at
`/preferences`.

**Full teardown**: set `enabled = false` in
`config/self-hosted/searxng.nix`, rebuild --
`mkTeardownActivationScript` (`../self-hosted.nix`) removes `venvDir`,
`srcDir`, and everything under `dataDir` not covered by `storage`
automatically. The real `settings.yml` inside the vault is never
touched by this. Flip `enabled` back to `true` and rebuild again to
reinstall (a fresh clone/venv/theme-link only happens because `srcDir`/
`venvDir` are actually gone, not because of anything special about
reinstall vs. install).
