# ComfyUI -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./comfyui.nix`. FHS sandbox: `./fhs.nix`.
Real values + node/model catalogs: `Nixos/config/self-hosted/comfyui/{comfyui,nodes,models}.nix`.
Lockfile: `Python/locks/self-hosted/comfyui/requirements.lock`.

The most involved service in this tree: a pinned core, a catalog of 69
custom nodes and ~87 models (only a subset of which is actually
"installed" at any time -- see "Store vs. installed" below), a
CUDA-enabled FHS sandbox, and by far the largest action set of any
service here -- `install`, `sync`, `sync:nodes`, `sync:models`,
`uninstall`, `uninstall:data`, plus every `update*` action doubled into a
print variant and a `:apply` variant that writes the change directly
(`update`, `update:apply`, `update:core`, `update:core:apply`,
`update:nodes`, `update:nodes:apply`, `update:nodes:<repo>`,
`update:nodes:<repo>:apply` per node, `update:deps`, `update:deps:apply`).
Everything below assumes you've read
`modules/services/self-hosted/self-hosted.nix`'s comments for the generic
mechanisms (`mkSelfHostedService`, `mkActionService`, `mkFHSVenv`,
`mkVenvInstallScript`) -- this file only covers what's specific to ComfyUI.

## Options (`vars.selfHosted.comfyui`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | `true` | Master switch. |
| `dataDir` | str | `~/Applications/Networking/ComfyUI` | Writable base. Holds `custom_nodes/` (symlinks), `models/`, `user/` (via storage), and is passed as ComfyUI's `--base-directory`. |
| `venvDir` | str | `~/.impure/python-venvs/self-hosted/comfyui` | Disposable, regenerable via `@install`. See "`~/.impure/`" below. |
| `autoStart` | bool | `true` | |
| `environment` | attrsOf str | `{ }` | Passthrough env, merged with the fixed `toolchainEnv` (CC/CXX/CUDA_HOME/TORCH_CUDA_ARCH_LIST/etc, see `comfyui.nix`). |
| `storage` | listOf `{src,dest}` | `[ ]` | Currently one entry: `user` -> the SelfHosted vault. |
| `requireMounts` | listOf str | `[ ]` | Mountpoint check before preStart -- the SelfHosted vault. |
| `coreRev` | str | *required* | Pinned `comfyanonymous/ComfyUI` git rev. |
| `coreHash` | str | *required* | `fetchFromGitHub` SRI hash for `coreRev`. |
| `nodeStore` | listOf `{owner,repo,rev,hash}` | `[ ]` | **Catalog** of every node ever pinned, whether or not currently active. `repo` also becomes the `custom_nodes/` directory name and the addressable key for `installed.nodes`. |
| `modelStore` | listOf `{name,type,url,target}` | `[ ]` | **Catalog** of every model ever pinned (~700GB across all of them). `type` is `hf`\|`civitai`\|`git`\|`url`. `target` is relative to `dataDir`. `name` is the addressable key for `installed.models` -- not required to be unique, entries sharing a name are one logical model split across files. |
| `installed.nodes` | listOf str | `[ ]` | `repo` values from `nodeStore` that actually get symlinked into `custom_nodes/`. Unknown name = hard eval-time error. |
| `installed.models` | listOf str | `[ ]` | `name` values from `modelStore` that `@sync` fetches and `@cleanup` keeps. Unknown name = hard eval-time error. |

**Store vs. installed**: `nodeStore`/`modelStore` (`./nodes.nix`, `./models.nix`) are
a catalog -- every pin you've ever made, kept around whether or not you
currently want it materialized. `installed.nodes`/`installed.models`
(`./comfyui.nix`) is the actually-active subset. This split exists
specifically for models -- there's no world where all ~700GB of them are
wanted on disk at once, so disabling one is a one-line removal from
`installed.models` (plus an explicit `@cleanup` to actually reclaim the
disk space) rather than deleting its pin and having to re-derive the URL
later. Nodes get the same treatment for consistency, even though in
practice all of them tend to be installed together.

## systemd units

- `self-hosted-comfyui.service` -- the live process. `preStart` re-syncs
  `custom_nodes/` on **every** start (cheap, no network -- see below).
- `self-hosted-comfyui@install` -- wipe+recreate `venvDir`,
  `pip install --require-hashes` the lockfile, then a separate
  `--no-deps` install of 4 packages that can't be hash-checked (see
  "Packages that can't be hashed" below).
- `self-hosted-comfyui@sync` -- both of the below, nodes first (cheap,
  no network) then models.
- `self-hosted-comfyui@sync:nodes` -- exactly what `preStart` already
  does on every service start (symlink `installed.nodes` into
  `custom_nodes/`, remove stale ones), exposed here so it's callable
  without a full restart.
- `self-hosted-comfyui@sync:models` -- fetch every `installed.models`
  entry that's missing (or corrupt/undersized), **then** remove any file
  under `dataDir/models/` that isn't backing a current `installed.models`
  entry. Both directions in one action -- there used to be a separate
  `@cleanup` for the removal half (mirroring the old bash's
  `plugins.sh`/`cleanup.sh` split), merged once the store/installed split
  made "declared list shrinks" mean "deliberately deactivated, pin still
  safe in `modelStore`" rather than "oops, lost the pin forever."
- `self-hosted-comfyui@uninstall` -- removes `venvDir`, `custom_nodes/`,
  and everything under `dataDir/models/` -- i.e. everything `@install`/
  `@sync` put there. Leaves anything covered by `storage` (`user/`)
  alone. Recoverable: `@install` + `@sync` bring it all back from the
  same pins.
- `self-hosted-comfyui@uninstall:data` -- tier 1, plus what `storage`
  actually points at: the real `user/` vault content. **Not
  recoverable.**
- `self-hosted-comfyui@update` -- `update:core`, then `update:nodes`,
  then `update:deps`, in that order.
- `self-hosted-comfyui@update:core` -- checks `comfyanonymous/ComfyUI`'s
  default branch for a newer commit than `coreRev`.
- `self-hosted-comfyui@update:nodes` -- same check, for every node in
  `installed.nodes` (matches what `@sync:nodes` actually keeps in sync).
- `self-hosted-comfyui@update:nodes:<repo>` -- same check for one
  specific node, by its `repo` name. Works for *any* `nodeStore` entry,
  installed or not -- checking a catalog entry before activating it is a
  real use case.
- `self-hosted-comfyui@update:deps` -- re-runs pip-compile against the
  current `installed.nodes`' requirements, diffs against the checked-in
  lock.

Every action above is **print/diff-only** by default -- none of them
write `config/self-hosted/comfyui/{comfyui,nodes}.nix` or
`requirements.lock` on their own. Read the output (`journalctl -u
self-hosted-comfyui@<action>`), paste/apply what you want by hand,
rebuild.

Each also has a `:apply` counterpart that does the same check but writes
the change directly instead of just printing it: `update:apply` (core +
installed nodes + deps, in order), `update:core:apply`,
`update:nodes:apply` (every installed node), `update:nodes:<repo>:apply`
(one specific node, any catalog entry), `update:deps:apply`. These
`sed`-edit `config/self-hosted/comfyui/comfyui.nix` or `nodes.nix`
directly (deps writes `requirements.lock` directly, same as OpenWebUI's
`@update:apply`) -- still never rebuilds, restarts, or runs `@install` on
their own, that stays a separate, deliberate step.

## `--base-directory`

`main.py` runs straight from the read-only Nix store
(`comfyCore = fetchFromGitHub {...}`). ComfyUI's own `--base-directory`
flag (confirmed in `comfy/cli_args.py`, not assumed) redirects its
`models/`, `custom_nodes/`, `input/`, `output/`, `temp/`, `user/` lookups
at `dataDir` instead of wherever `main.py` lives -- this is what lets the
core source stay a plain immutable store path while still having writable
data. If a node writes into its *own* source directory (not `dataDir`),
that will fail (EROFS) -- no known case of this yet; if one shows up, it
needs the same kind of per-node patch as the font fix below, not a
generic workaround.

## Node symlinking (every start, not just `@sync`)

`custom_nodes/<repo>` is a symlink straight to that node's Nix store path
(patched first if it's the one node that needs it). Rebuilt on every
`self-hosted-comfyui` start, operating on `installed.nodes`, not the full
`nodeStore`:
- Every node in `installed.nodes` gets `ln -sfn` (idempotent, cheap).
- Any symlink in `custom_nodes/` for a node no longer in `installed.nodes`
  gets removed -- whether it was dropped from `nodeStore` entirely or
  just deactivated.

This is safe to do unconditionally because it's pure symlinking against
already-fetched store paths -- no network, no risk of losing data (unlike
the models half of `@sync`, which does real network I/O and can be slow
-- that's why `@sync:nodes` exists separately, to reconcile nodes without
waiting on models). One consequence: **adding or removing a node takes
effect on the next service restart (or `@sync`/`@sync:nodes`), not on
rebuild alone.**

## The one patched node

`ComfyUI-post-processing-nodes` hardcodes `ImageFont.truetype("arial.ttf", ...)`.
The old bash relied on an Arch-specific hook symlinking system fonts into
`/usr/share/fonts/truetype`; here, `mkNodeSrc` in `comfyui.nix` instead
`sed`-patches that one line to a real `dejavu_fonts` store path at build
time. No generic per-node patch mechanism exists -- this is a plain
`if node.repo == "..." then ... else ...` lookup. If a second node needs a
similar patch, extend that same `mkNodeSrc`, don't build a framework for
one more case.

## Packages that can't be hashed

pip's `--require-hashes` mode rejects a requirements file if even one
package lacks a hash, and it fundamentally cannot hash-check a VCS (git)
reference the way it can a sdist/wheel URL. Four packages -- pulled in by
`ComfyUI-Impact-Pack`'s and `was-node-suite-comfyui`'s own
`requirements.txt`, both unpinned upstream -- had to come out of the
compiled lock entirely:

- `git+https://github.com/facebookresearch/sam2`
- `git+https://github.com/ltdrdata/img2texture.git`
- `git+https://github.com/ltdrdata/cstr`
- `git+https://github.com/ltdrdata/ffmpy.git`

Each is pinned to a real commit (the old bash never pinned these either --
floating HEAD on every install -- so this is strictly more reproducible,
just not hash-verified) and installed with `pip install --no-deps` as a
separate step in `@install`, after the main hash-locked install. `--no-deps`
matters: their actual dependencies (torch, hydra-core, omegaconf, iopath,
...) are already resolved and hash-locked by the main install: letting pip
re-resolve here could silently install a different version than the one
actually locked.

## Updating `requirements.lock`

`requirements.in` is **not** a checked-in file for ComfyUI -- unlike
OpenWebUI's, it depends on the *installed* nodes' own `requirements.txt`
content, and a hand-maintained second copy of that would just drift from
`nodes.nix`/`comfyui.nix` (the actual source of truth). It's a Nix
derivation instead (`comfyRequirementsIn` in `comfyui.nix`), built from
each `installed.nodes` entry's already-pinned source plus a small static
header (torch/CUDA index + the old `PYTHON_REQUIREMENTS`/`PROTECTED_LIBS`
values), with two fixups baked in (`ComfyUI-BrushNet`'s conflicting
`accelerate` pin relaxed; the 4 git deps above stripped out). Only
currently-installed nodes are included -- toggling a node off also
shrinks the dependency set that needs resolving/locking.

`systemctl start self-hosted-comfyui@update:deps:apply` runs the whole
thing and writes the result: builds `comfyRequirementsIn`, runs
pip-compile, diffs against the checked-in lock, and if it differs, moves
the new one straight into `requirements.lock`. Use bare `@update:deps`
first if you want to see the diff (`requirements.lock.new` +
`journalctl -u self-hosted-comfyui@update:deps`) before committing to it.
Same shape as OpenWebUI's `@update`/`@update:apply`
(`../self-hosted.nix`'s `mkDepsUpdateScript`).

Run it after adding/activating a node, bumping a node's pinned `rev`, or
bumping `coreRev` -- any of those can change what needs resolving.

Expect new conflicts occasionally -- the old bash's own comments document
at least one known node-vs-node version fight, and the accelerate/BrushNet
one above was found the same way: `pip-compile` just fails loudly with
exactly which two constraints disagree (visible in `journalctl`). Fix by
relaxing the losing side's constraint in the header or (if it's a node's
own `requirements.txt` that's the problem) adding a targeted `sed` fixup
next to the two that already exist in `comfyRequirementsIn`
(`comfyui.nix`).

## Workflows

**Pin a new node into the catalog (not yet active)**: get `rev`+`hash`
(`nix-shell -p nix-prefetch-git --run "nix-prefetch-git --url
https://github.com/<owner>/<repo> --rev <rev> --quiet"`), append to
`config/self-hosted/comfyui/nodes.nix` (`nodeStore`). It sits there,
pinned but inert, until added to `installed.nodes`.

**Check/bump a pinned node's commit**: `systemctl start
self-hosted-comfyui@update:nodes:<repo>` (any `nodeStore` entry, active
or not) prints the new `rev`/`hash` if one exists
(`journalctl -u self-hosted-comfyui@update:nodes:<repo>`).
`@update:nodes:<repo>:apply` does the same check and `sed`-writes the new
`rev`/`hash` into that exact entry in `nodes.nix` directly.
`@update:nodes`/`@update:nodes:apply` do every *installed* node in one
run instead of one at a time.

**Activate/deactivate a pinned node**: add/remove its `repo` in
`installed.nodes` (`config/self-hosted/comfyui/comfyui.nix`), rebuild,
then either restart the service or `systemctl start
self-hosted-comfyui@sync:nodes` -- `custom_nodes/` symlinks reconcile
either way. Activating a node with its own `requirements.txt` also needs
a `requirements.lock` regeneration (above) + `@install`, or it'll be
symlinked but fail to import at runtime.

**Drop a node from the catalog entirely**: remove it from both
`installed.nodes` and `nodeStore`. If it's only removed from
`installed.nodes`, it deactivates but stays pinned for later.

**Pin a new model into the catalog (not yet installed)**: append
`{ name, type, url, target }` to `config/self-hosted/comfyui/models.nix`
(`modelStore`). Costs nothing until it's in `installed.models`.

**Install/remove a pinned model from disk**: add/remove its `name` in
`installed.models` (`comfyui.nix`), rebuild, then `systemctl start
self-hosted-comfyui@sync:models` (or bare `@sync`, which also does
nodes). One action handles both directions: newly-added names get
fetched, newly-removed names get their file deleted in the same run.
Shrinking `installed.models` and re-running `@sync:models` is fully
reversible either way -- the pin stays in `modelStore` regardless, only
the file on disk comes and goes.

**Full teardown, including the real data**: `systemctl start
self-hosted-comfyui@uninstall:data` -- deletes the actual `user/` vault
content (workflows, prompts you've saved), not just the venv/nodes/models.
Think before running it.

**Bump the ComfyUI core version**: `systemctl start
self-hosted-comfyui@update:core:apply` writes the new `coreRev`/`coreHash`
into `config/self-hosted/comfyui/comfyui.nix` directly (bare
`@update:core` first if you want to see it before it lands). Consider
`@update:deps:apply` too, since core's own `requirements.txt` is part of
the compiled set.

## `~/.impure/`

`venvDir` deliberately lives outside `dataDir`, under
`~/.impure/python-venvs/self-hosted/comfyui/`. A venv is exactly what that
directory exists to hold: real files on disk that Nix did not create and
cannot fully account for (pip-installed packages, not derivations),
structurally separated from `dataDir`'s declared/backed-up data so nothing
ever conflates the two.
