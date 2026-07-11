# self-hosted -- how it all works

Four services live under this framework today: Ollama, Stash, OpenWebUI,
ComfyUI. This document explains the shared machinery all of them are
built from. For any one service's specific options/actions, read its own
`<name>/info.md` instead -- this file only covers what's common.

## The two-tree split

Every service is split across two directories, same reasoning as the
rest of this repo (`modules/` vs `config/` generally):

- **`Nixos/modules/services/self-hosted/<name>/`** -- schema (`default.nix`)
  and logic (`<name>.nix`, plus whatever else the service needs:
  `package.nix`, `fhs.nix`, `sync.nix`, `update.nix`). This is the code.
  It has no opinion about what version to pin, what models to fetch, or
  where data lives -- it just defines the *shape* those decisions take
  and what happens once they're filled in.
- **`Nixos/config/self-hosted/<name>.nix`** (or `<name>/` when one file
  isn't enough, e.g. ComfyUI's `nodes.nix`/`models.nix`) -- the actual
  values for *this* machine. Plain data: strings, lists, attrsets. Never
  a `pkgs.fetchFromGitHub`, never a `pkgs.runCommand`, never a
  conditional. If you find yourself writing logic in `config/`, that
  logic belongs in the module instead -- see `docs/conventions.md`.

`modules/services/self-hosted/default.nix` and `config/self-hosted/default.nix`
each just `imports` every service's subdirectory/file -- adding a service
means adding one line to each.

## `self-hosted.nix`: the shared function library

`modules/services/self-hosted/self-hosted.nix` is **not** a NixOS module
-- it has no `options`/`config`, just a `rec { ... }` of plain functions.
Every service's `<name>.nix` imports it directly
(`import ../self-hosted.nix { inherit lib pkgs; }`) and calls a handful
of these to assemble its actual systemd units. This is deliberately the
*only* place the "how" of running a self-hosted service as systemd is
written -- a new service calls these with its own values, it doesn't
reimplement unit-building.

### `mkSelfHostedService` -- the live process

One systemd service (`self-hosted-<name>.service`), `Restart=on-failure`.
Takes `execStart`, `user`, and the generic bits every service might need:
`packages`, `environment`, `preStart` (ordered `ExecStartPre` list),
`storage` (tmpfiles `L+` symlink rules), `requireMounts` (mountpoint
checks run before anything else, generic -- knows nothing about Casket
or vaults specifically), `environmentFile` (root-owned secrets, see
below), `dataDir`/`ensureDataDir`/`autoStart`.

**The `ensureDataDir` trap**: `true` gets you a tmpfiles `d` rule for
`dataDir` plus `WorkingDirectory=dataDir` on the unit -- convenient, but
`WorkingDirectory=` applies to *every* exec step including
`ExecStartPre`. If `dataDir` is gated by something external (a Casket
vault that might not be mounted yet), a preStart meant to check for that
can't even run, because the working directory itself doesn't exist yet.
Found this the hard way (Stash and Ollama both hit exit 200/CHDIR on a
real rebuild) -- see the option's own comment in `self-hosted.nix` for
the exact failure mode. Rule of thumb: `ensureDataDir = true` only if
`dataDir`'s existence isn't conditional on anything outside Nix's
control.

### `mkActionService` -- manual actions, one dispatch script

One systemd **template** unit (`self-hosted-<name>@.service`) per
service, not one unit per action. `actions` is a plain `attrsOf str` --
action name to script body -- compiled into a single dispatch script that
does `case "$1" in <action>) exec <script> ;; ... esac`. `systemctl start
self-hosted-<name>@<action>` (or the `@` form, same thing) runs it.
**Never** `wantedBy`, **never** a dependency of the live service or of
system activation -- a rebuild only ever changes what's *declared*,
never triggers a fetch, install, or sync on its own.

**Why one dispatch script instead of separate unit names**: groups
everything under one unit family (`self-hosted-<name>@*`) instead of
scattering independent top-level service names, and it means the actual
mechanism (`case` statement matching a literal string) is completely
generic -- see "Action naming" below for how far this stretches.

### `mkFHSVenv` / `mkVenvInstallScript` -- the one deliberately-impure step

Python services (OpenWebUI, ComfyUI) need pip-installed compiled wheels
that expect a real `/lib`, `/usr/lib` FHS layout, which doesn't exist on
NixOS. `mkFHSVenv` wraps `pkgs.buildFHSEnv` -- this derivation itself is
pure and reproducible (a symlink+bind-mount merge of `targetPkgs`, not
copies). `mkVenvInstallScript` runs inside that sandbox: wipe `venvDir`,
create a fresh venv, `pip install --require-hashes -r requirementsLock`.

This is **the one place in the whole system that's allowed to be
impure** -- what pip actually resolves and installs isn't reproducible
the way a Nix derivation is. It's structurally confined: `execStart`
never references the venv as a Nix derivation, only `venvDir` (a plain
path) is used, so a broken or stale lock can only ever fail the
`@install` action -- it can never block `nixos-rebuild switch` for the
rest of the system.

`venvDir` lives under `~/.impure/python-venvs/self-hosted/<name>/`, not
under `dataDir` -- see "`~/.impure/`" below.

`mkFHSVenv` also takes `extraBwrapArgs ? [ ]`, forwarded straight to
`buildFHSEnv` (a real, existing option there, confirmed via its own
`__functionArgs`, not assumed). Use this when something needs to be
bind-mounted at a specific in-sandbox path rather than symlinked on the
real filesystem -- a plain symlink is transparent to most things, but
not to code that calls `Path(...).resolve()` and expects the result to
look like a normal, real install layout (`.resolve()` follows the
symlink through to wherever it actually points, which for anything
fetched via Nix is the store, not the meaningful path). ComfyUI's
`custom_nodes/` is the first real use of this -- see its own `info.md`'s
"Node mounting" section for the full story, including a real bug two
nodes hit from exactly this. The mechanism itself is generic and lives
here precisely so any other FHS-based service hitting the same problem
doesn't need its own bespoke fix.

### `mkUninstallScript` -- two-tier teardown, every service gets it

```nix
mkUninstallScript = { dataDir, storage ? [ ], venvDir ? null, includeData ? false }
```

- **Tier 1** (`@uninstall`): `venvDir` (if any) plus everything directly
  under `dataDir` *except* whatever a `storage` entry's `src` covers.
  I.e. exactly what `@install`/`@sync` put there. Recoverable -- the
  pins are untouched, re-running those actions brings it all back.
- **Tier 2** (`@uninstall:data`, `includeData = true`): tier 1, plus what
  each `storage` entry's `dest` actually points at -- the real data this
  service was fronting (a vault-resident database, chat history, saved
  workflows). **Not recoverable.** Always includes tier 1 too, so it's a
  complete teardown regardless of whether tier 1 already ran.

Both are idempotent (`rm -rf` on an already-missing path is a no-op), so
they're safe to run in either order or independently. Neither ever
touches the Nix store -- reclaiming unused store paths is garbage
collection's job (`pacnix orphaned`), not this.

### `mkDepsUpdateScript` -- shared by every pip-based service

```nix
mkDepsUpdateScript = { serviceName, requirementsIn, requirementsLock, requirementsLockPath, apply ? false }
```

Re-runs pip-compile against `requirementsIn`, diffs the result against
the checked-in `requirementsLock`. `apply = false`: print/diff only,
leaves the new lock at `<requirementsLockPath>.new` if it differs.
`apply = true`: same check, but moves the new lock into place directly.

`requirementsIn`/`requirementsLock` are Nix *paths* (fine to reference
directly -- pip-compile and `diff` only ever read them, and Nix's own
copy-to-store for path interpolation is exactly what you want for a pure
read). `requirementsLockPath` is deliberately a **plain string** -- the
real filesystem path in the actual Dotfiles checkout. This distinction
matters: `${requirementsLock}` (the Nix path) resolves to a read-only
`/nix/store/HASH-requirements.lock` copy. Writing `.new` "next to" that,
or moving a new file "into" it, would either write into the read-only
store (impossible) or land somewhere nobody would ever look. Every
script in this system that *writes* to a config/lock file takes the real
path as a separate plain-string parameter for this exact reason -- see
`docs/conventions.md`.

## Action naming: `:target` and `:apply`

Every service's actions live in one flat `attrsOf str`, dispatched by a
single `case "$1" in ... esac`. Nothing about that mechanism knows about
colons specifically -- `"sync:models"`, `"update:nodes:ComfyUI-Manager:apply"`
are just attrset keys like any other, matched as literal strings. Two
conventions have been layered on top of that plain mechanism, both
verified against real systemd behavior (not assumed):

- **`:target`** -- narrows an action to one part of what it'd otherwise
  do in full. `sync` (bare) does everything sync-able; `sync:models`
  does just the models half. `update:nodes:<repo>` narrows all the way
  down to one specific node. The bare form should always be "do
  everything the targeted forms can do, in a sensible order" -- never a
  separate, different behavior.
- **`:apply`** -- every `update*` action exists in a print-only form and
  an `:apply` form that performs the same check but writes the result
  (`sed`-edits a config `.nix` file, or moves a new lockfile into place)
  instead of just printing it. `update:core` and `update:core:apply` run
  the identical check; only what happens with a positive result differs.

**Why colons and not `=` or `!`**: verified directly against
`systemd.unit(5)` and with live throwaway units before committing to
this. Systemd unit (and instance) names are restricted to `[A-Za-z0-9:_.\-]`
-- `:` is explicitly valid and never escaped; `=` and `!` are both
rejected outright by `systemctl start` ("Invalid unit name... maybe you
should use systemd-escape?"), not silently accepted or auto-escaped.
Chained colons (`a:b:c`) work fine -- there's no limit on how many
segments. If a future convention needs a new separator, verify it the
same way (`systemd-escape --template` plus an actual throwaway
`systemctl --user start` test) before relying on it -- don't assume from
the character class alone.

**`:apply` never rebuilds or restarts anything.** Writing a change into
a source file and actually deploying that change (`nixos-rebuild` +
service restart) are always two separate, deliberate steps. No action in
this system ever triggers a rebuild.

## The store/installed split (ComfyUI's `nodeStore`/`modelStore`)

ComfyUI's nodes and models are each split into a **catalog**
(`nodeStore`/`modelStore` in `config/self-hosted/comfyui/{nodes,models}.nix`
-- every pin ever made, whether or not currently wanted) and an
**installed subset** (`installed.nodes`/`installed.models` in
`comfyui.nix` -- what's actually mounted/fetched right now). This
exists specifically because ComfyUI's model catalog is ~700GB and
there's no realistic scenario where all of it is wanted on disk
simultaneously -- disabling a model is a one-line removal from
`installed.models` (plus an explicit `@sync:models` or `@sync` to
actually reclaim the disk space), not deleting its pin and having to
re-derive the download URL later. Nodes get the identical treatment for
consistency, even though in practice they tend to be installed together.

This is **not** the default shape for a new service -- Ollama and Stash
don't have it, because neither has a "catalog vastly larger than what's
wanted at once" problem. Only add a store/installed split when that
specific problem actually exists; see `docs/conventions.md` on avoiding
generalization nobody asked for.

Every `installed.*` entry is checked against its catalog with a real
`assertions` entry -- a typo'd name is a hard rebuild-time error, not a
silent no-op. If a new service ever needs this pattern, copy that
assertion shape too, not just the filter.

## Secrets

A service that needs a real secret (an API token, not a password) gets
`environmentFile` on `mkSelfHostedService`/`mkActionService` --
`EnvironmentFile = "-${path}"` (the `-` prefix makes a missing file a
non-error, not a startup failure). Nix only ever knows the *path*
(`/etc/nixos-secrets/self-hosted/<name>/tokens.env`), never the value --
same split as the login password's `hashedPasswordFile`. The file itself
is written by `secrets self-hosted <name>` (`Scripts/Secrets/cmd/self-hosted.sh`),
a generic masked-prompt command that works for any service name without
modification, root-owned 600.

## `~/.impure/`

Every venv (`OpenWebUI`, `ComfyUI`) lives under
`~/.impure/python-venvs/self-hosted/<name>/`, not under that service's
own `dataDir`. This directory name is the explicit signal: everything
under it is real files on disk that Nix did not create and cannot fully
account for (pip-installed packages, not derivations) -- structurally
separated from `dataDir`'s declared, backed-up, Nix-adjacent data so
nothing ever conflates the two. If a future service needs some other
kind of genuinely-impure on-disk state that isn't a venv, it likely
belongs under `~/.impure/` too, in its own subdirectory.

## What a request actually does, end to end

`systemctl start self-hosted-comfyui@sync:models` ->
1. Starts the `self-hosted-comfyui@.service` template instance
   `sync:models`.
2. Its `ExecStart` is the one shared dispatch script
   (`self-hosted-comfyui-dispatch %i`) built by `mkActionService`.
3. The dispatch script's `case "$1" in ... "sync:models") exec ... ;;`
   matches the literal string `sync:models` and execs that action's own
   `writeShellScript` derivation.
4. That script runs as a oneshot, with whatever `packages`/`environment`/
   `environmentFile` the service's `mkActionService` call declared.
5. Nothing about steps 1-4 changes when a new action is added to a
   service -- it's purely a new key in that service's `actions` attrset.
