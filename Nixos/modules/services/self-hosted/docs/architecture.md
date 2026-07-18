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
-- it has no `options`/`config`, just a plain re-export of functions
(originally one big `rec { ... }`, split into `./lib/service/mk-*.nix`
and `./lib/venv/mk-*.nix` once the file passed ~400 lines -- see its own
top comment for the split and why each function lives where it does).
Every service's `<name>.nix` imports it directly
(`import ../self-hosted.nix { inherit lib pkgs; }`) and calls a handful
of these to assemble its actual systemd units. This is deliberately the
*only* place the "how" of running a self-hosted service as systemd is
written -- a new service calls these with its own values, it doesn't
reimplement unit-building.

### `mkSelfHostedService` -- the live process

One systemd service (`self-hosted-<name>.service`), `Restart=on-failure`,
`TimeoutStartSec=infinity` (systemd's default 90s start timeout was
killing a legitimately-long first-time venv install mid-download,
confirmed on a real ComfyUI run -- see its own `info.md` -- preStart
taking a long time on first install, or after a lock change, is expected
for any service with a hash-locked venv, not a hang, so the timeout is
disabled entirely rather than guessing at a large-enough fixed value).
Takes `execStart`, `user`, and the generic bits every service might need:
`packages`, `environment`, `preStart` (ordered `ExecStartPre` list),
`postStart` (ordered `ExecStartPost` list -- see below), `storage`
(tmpfiles `L+` symlink rules), `requireMounts` (mountpoint checks run
before anything else, generic -- knows nothing about Casket or vaults
specifically), `environmentFile` (root-owned secrets, see below),
`dataDir`/`ensureDataDir`/`autoStart`/`homeDirectory`, and
`enabled`/`teardownPaths`/`venvDir` (the enabled/disabled lifecycle, see
"No uninstall action" below).

**`preStart` vs `postStart`**: both are just ordered lists of shell
strings, each wrapped in its own `writeShellScript` -- the only real
difference is *when* systemd runs them. `ExecStartPre` (preStart) runs
before the main process forks; use it for anything that only needs the
filesystem (venv install/reconcile, node/model mounting). `ExecStartPost`
(postStart) runs right after fork/exec, **not** once the process is
actually ready to serve -- use it only when reconciliation has to go
through the live process's own interface (Ollama's model sync goes
through `ollama list`/`ollama pull` over its HTTP API, which isn't up the
instant the binary forks). Anything using `postStart` for this reason
needs its own bounded poll-until-ready loop first (see `ollama/lib/sync.nix`)
-- `ExecStartPost` gives you no such guarantee for free.

**`homeDirectory`**: when set, `mkSelfHostedService` computes every path
component strictly between `homeDirectory` and `dataDir` and emits a
`d`+`z` tmpfiles rule pair for each ancestor, not just `dataDir` itself.
Exists because an ancestor directory (e.g. `~/Applications`) can end up
root-owned from some earlier root-run step, and `systemd-tmpfiles` refuses
to walk through a root-owned parent to fix a child ("unsafe path
transition") -- fixing just the leaf `dataDir` silently doesn't work if
any ancestor above it is wrong. Pass `homeDirectory = config.vars.identity.homeDirectory;`
whenever `dataDir` lives under the home directory.

**The `ensureDataDir` trap**: `true` gets you a tmpfiles `d` rule for
`dataDir` plus `WorkingDirectory=dataDir` on the unit -- convenient, but
`WorkingDirectory=` applies to *every* exec step including
`ExecStartPre`/`ExecStartPost`. If `dataDir` is gated by something
external (a Casket vault that might not be mounted yet), a preStart meant
to check for that can't even run, because the working directory itself
doesn't exist yet. Found this the hard way (Stash and Ollama both hit
exit 200/CHDIR on a real rebuild) -- see the option's own comment in
`self-hosted.nix` for the exact failure mode. Rule of thumb:
`ensureDataDir = true` only if `dataDir`'s existence isn't conditional on
anything outside Nix's control.

**`requireMounts`**: when non-empty, `mkSelfHostedService` automatically
adds `pkgs.util-linux` to the unit's `path` -- the mountpoint check shells
out to `mountpoint`, which isn't on PATH by default. No caller has to
remember this.

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

### `mkFHSVenv` / `mkVenvInstallScript` / `mkVenvEnsureScript` -- the one deliberately-impure step

Python services (OpenWebUI, ComfyUI) need pip-installed compiled wheels
that expect a real `/lib`, `/usr/lib` FHS layout, which doesn't exist on
NixOS. `mkFHSVenv` wraps `pkgs.buildFHSEnv` -- this derivation itself is
pure and reproducible (a symlink+bind-mount merge of `targetPkgs`, not
copies). `mkVenvInstallScript` runs inside that sandbox: wipe `venvDir`,
create a fresh venv, `pip install --require-hashes -r requirementsLock`,
then writes `requirementsLock`'s hash (computed at eval time via
`builtins.hashFile`) to a marker file in `venvDir` on success.

`mkVenvEnsureScript` wraps that: compares the marker file against the
lock's current hash first, and only runs the real (slow) install if
they differ. Every service's `preStart` calls this, not
`mkVenvInstallScript` directly -- there's no separate manual install
action, the venv reconciles itself on every service start, and stays a
no-op the moment `requirementsLock` hasn't actually changed.

This is **the one place in the whole system that's allowed to be
impure** -- what pip actually resolves and installs isn't reproducible
the way a Nix derivation is. It's structurally confined: `execStart`
never references the venv as a Nix derivation, only `venvDir` (a plain
path) is used, so a broken or stale lock can only ever fail that
service's own `preStart` -- it can never block `nixos-rebuild switch`
for the rest of the system.

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

### No *manual* uninstall action -- but `enabled` drives a real one

There used to be a two-tier manual `mkUninstallScript` (`@uninstall`/
`@uninstall:data`). That's gone for good, not narrowed -- but "no
uninstall at all" (an earlier, stricter version of this section) turned
out to be wrong too: nodes/models removal-when-undeclared being fully
automatic via preStart (verified empirically -- created fake undeclared
node/model fixtures, ran the real generated preStart scripts, confirmed
both got removed with real command output) and the venv rebuilding
itself on lock change via `mkVenvEnsureScript` only cover *some* of what
uninstall used to do. What was still missing -- a real way to tear down
the rest (the venv itself, mounted nodes, fetched models -- everything
`preStart` would otherwise just reinstall on the next start) without
ever risking genuinely precious content (ComfyUI's `output/`, `temp/` --
actual generated images, ComfyUI's dataDir isn't the only case where
this matters) -- is `mkTeardownActivationScript`, driven by the
`enabled` option itself, not a separate action:

- `enabled = false` + rebuild -> `mkTeardownActivationScript` runs as a
  `system.activationScripts` entry (the one place that still runs on
  every `nixos-rebuild switch` regardless of whether this service's own
  systemd unit exists this generation -- can't live in `preStart`, since
  when `enabled = false` the whole live-service config block, `preStart`
  included, doesn't exist at all) and removes `venvDir` (if any) plus
  whatever `teardownPaths` declares.
- `teardownPaths` (a real per-service option, `listOf str`, default
  `[ ]`) controls the blast radius explicitly, as data, not a hardcoded
  rule: empty means "everything directly under `dataDir` except what a
  `storage` entry covers" (safe for services whose `dataDir` holds
  nothing else -- Ollama, OpenWebUI, Stash, confirmed by their own
  `dataDir` doc comments, not assumed); non-empty scopes it to exactly
  those paths instead, storage or not (ComfyUI needs this: `dataDir`
  also holds `output`/`temp`/`input`, real content no `storage` entry
  covers, that the empty-default rule would otherwise destroy).
- `enabled = true` + rebuild + restart brings it all back automatically
  -- the same `preStart` reconciliation that runs on every start doesn't
  know or care whether this is a first install or a reinstall after a
  teardown.

The safety principle from the old (stricter) version of this section
still holds, just enforced through `teardownPaths` as explicit data
instead of a blanket rule: anything genuinely precious and
non-reconcilable must never be reachable by this path -- if a service
generates something like that, it either needs a `storage` entry, or an
explicit gap in `teardownPaths`, never an assumption that "the rest of
dataDir is safe to wipe."

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
colons specifically -- `"update:nodes"`, `"update:nodes:ComfyUI-Manager:apply"`
are just attrset keys like any other, matched as literal strings. Two
conventions have been layered on top of that plain mechanism, both
verified against real systemd behavior (not assumed):

- **`:target`** -- narrows an action to one part of what it'd otherwise
  do in full. `update` (bare) checks core, installed nodes, and deps all
  at once; `update:nodes` checks just the nodes; `update:nodes:<repo>`
  narrows all the way down to one specific node. The bare form should
  always be "do everything the targeted forms can do, in a sensible
  order" -- never a separate, different behavior. Note this convention is
  only about `@update*` now -- there's no `sync`/`install`/`uninstall`
  action family left to target at all, see the sections above.
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
`installed.models`, and the next service start's preStart (no separate
action needed) fetches whatever's newly declared and reclaims disk space
for whatever just dropped out, not deleting its pin and having to
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

## What actually happens on a rebuild + restart

This is the primary path now -- no manual action required at all:
`nixos-rebuild switch` -> `systemctl restart self-hosted-comfyui` ->
1. `ExecStartPre` (preStart) runs, in list order: mount/unmount
   `custom_nodes/` to match `installed.nodes`, run `venvEnsureScript`
   (no-op unless `requirementsLock`'s hash changed), fetch/remove models
   under `dataDir/models` to match `installed.models`.
2. `ExecStart` (the real ComfyUI process) starts.
3. Nothing about steps 1-2 needed you to run anything by hand -- editing
   `installed.nodes`/`installed.models`/`requirementsLock` in `config/`
   and rebuilding is sufficient on its own.

## What a manual action request actually does, end to end

`systemctl start self-hosted-comfyui@update:nodes` ->
1. Starts the `self-hosted-comfyui@.service` template instance
   `update:nodes`.
2. Its `ExecStart` is the one shared dispatch script
   (`self-hosted-comfyui-dispatch %i`) built by `mkActionService`.
3. The dispatch script's `case "$1" in ... "update:nodes") exec ... ;;`
   matches the literal string `update:nodes` and execs that action's own
   `writeShellScript` derivation.
4. That script runs as a oneshot, with whatever `packages`/`environment`/
   `environmentFile` the service's `mkActionService` call declared.
5. Nothing about steps 1-4 changes when a new action is added to a
   service -- it's purely a new key in that service's `actions` attrset.
   Remember: the only action family left is `@update*` -- checking
   upstream for something newer. Everything else is automatic, per the
   section above.
