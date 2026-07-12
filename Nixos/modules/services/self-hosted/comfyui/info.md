# ComfyUI -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./comfyui.nix`. Implementation detail
pieces: `./lib/{fhs,node-mounting,requirements,models-sync,update}.nix`.
Real values + node/model catalogs: `Nixos/config/self-hosted/comfyui/{comfyui,nodes,models}.nix`.
Lockfile: `Python/locks/self-hosted/comfyui/requirements.lock`.

The most involved service in this tree: a pinned core, a catalog of 69
custom nodes and ~87 models (only a subset of which is actually
"installed" at any time -- see "Store vs. installed" below), a
CUDA-enabled FHS sandbox, and by far the largest action set of any
service here -- every `update*` action doubled into a print variant and a
`:apply` variant that writes the change directly (`update`,
`update:apply`, `update:core`, `update:core:apply`, `update:nodes`,
`update:nodes:apply`, `update:nodes:<repo>`, `update:nodes:<repo>:apply`
per node, `update:deps`, `update:deps:apply`). That's the *entire* manual
action set -- node/model reconciliation and the venv install all happen
automatically via `preStart` now, no manual action for any of it. See
`../docs/architecture.md`'s "No uninstall action" and "What actually
happens on a rebuild + restart" for why. Everything below assumes you've
read `modules/services/self-hosted/self-hosted.nix`'s comments for the
generic mechanisms (`mkSelfHostedService`, `mkActionService`, `mkFHSVenv`,
`mkVenvEnsureScript`) -- this file only covers what's specific to ComfyUI.

## Options (`vars.selfHosted.comfyui`)

| Option | Type | Default | Notes |
|---|---|---|---|
| `enable` | bool | `true` | Master switch. |
| `dataDir` | str | `~/Applications/Networking/ComfyUI` | Writable base. Holds `custom_nodes/` (bind mounts), `models/`, `user/` (via storage), and is passed as ComfyUI's `--base-directory`. |
| `venvDir` | str | `~/.impure/python-venvs/self-hosted/comfyui` | Disposable, regenerated automatically by preStart's `venvEnsureScript` whenever `requirementsLock`'s hash changes. See "`~/.impure/`" below. |
| `autoStart` | bool | `true` | |
| `environment` | attrsOf str | `{ }` | Passthrough env, merged with the fixed `toolchainEnv` (CC/CXX/CUDA_HOME/TORCH_CUDA_ARCH_LIST/etc, see `comfyui.nix`). |
| `storage` | listOf `{src,dest}` | `[ ]` | Currently one entry: `user` -> the SelfHosted vault. |
| `requireMounts` | listOf str | `[ ]` | Mountpoint check before preStart -- the SelfHosted vault. |
| `coreRev` | str | *required* | Pinned `comfyanonymous/ComfyUI` git rev. |
| `coreHash` | str | *required* | `fetchFromGitHub` SRI hash for `coreRev`. |
| `nodeStore` | listOf `{owner,repo,rev,hash}` | `[ ]` | **Catalog** of every node ever pinned, whether or not currently active. `repo` also becomes the `custom_nodes/` directory name and the addressable key for `installed.nodes`. |
| `modelStore` | listOf `{name,type,url,target}` | `[ ]` | **Catalog** of every model ever pinned (~700GB across all of them). `type` is `hf`\|`civitai`\|`git`\|`url`. `target` is relative to `dataDir`. `name` is the addressable key for `installed.models` -- not required to be unique, entries sharing a name are one logical model split across files. |
| `installed.nodes` | listOf str | `[ ]` | `repo` values from `nodeStore` that actually get bind-mounted into `custom_nodes/`. Unknown name = hard eval-time error. |
| `installed.models` | listOf str | `[ ]` | `name` values from `modelStore` that preStart fetches and keeps on disk, removing anything backing a name no longer listed. Unknown name = hard eval-time error. |

**Store vs. installed**: `nodeStore`/`modelStore` (`./nodes.nix`, `./models.nix`) are
a catalog -- every pin you've ever made, kept around whether or not you
currently want it materialized. `installed.nodes`/`installed.models`
(`./comfyui.nix`) is the actually-active subset. This split exists
specifically for models -- there's no world where all ~700GB of them are
wanted on disk at once, so disabling one is a one-line removal from
`installed.models` (the next rebuild + restart reclaims the disk space
automatically, no separate action) rather than deleting its pin and
having to re-derive the URL later. Nodes get the same treatment for
consistency, even though in practice all of them tend to be installed
together.

## systemd units

- `self-hosted-comfyui.service` -- the live process. `preStart` runs, in
  order: `prepareNodeMountsScript` (mkdir/rm the `custom_nodes/<repo>`
  mount-point directories to match `installed.nodes`, cheap, no network --
  see "Node mounting" below, actual node content is bind-mounted in by the
  sandbox itself), `venvEnsureScript` (no-op unless `requirementsLock`'s
  hash changed since the last successful install), `syncModelsScript`
  (fetch every `installed.models` entry that's missing/corrupt/undersized,
  then remove any file under `dataDir/models/` not backing a current
  entry -- both directions, every start).
- `self-hosted-comfyui@update` -- `update:core`, then `update:nodes`,
  then `update:deps`, in that order.
- `self-hosted-comfyui@update:core` -- checks `comfyanonymous/ComfyUI`'s
  default branch for a newer commit than `coreRev`.
- `self-hosted-comfyui@update:nodes` -- same check, for every node in
  `installed.nodes`.
- `self-hosted-comfyui@update:nodes:<repo>` -- same check for one
  specific node, by its `repo` name. Works for *any* `nodeStore` entry,
  installed or not -- checking a catalog entry before activating it is a
  real use case.
- `self-hosted-comfyui@update:deps` -- re-runs pip-compile against the
  current `installed.nodes`' requirements, diffs against the checked-in
  lock.

Every `update*` action above is **print/diff-only** by default -- none of
them write `config/self-hosted/comfyui/{comfyui,nodes}.nix` or
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
`@update:apply`) -- still never rebuilds or restarts on their own, and
never needs a follow-up manual install either: the next restart's
preStart picks up the change automatically.

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

## Node mounting: bind mounts, not symlinks

`custom_nodes/<repo>` is a real **bind mount** (`--ro-bind`, via
`buildFHSEnv`'s `extraBwrapArgs`) straight to that node's Nix store path,
set up when the sandbox launches -- not a plain filesystem symlink. This
was a real bug fix, not a stylistic choice: a symlink there meant any
node computing its own location via `Path(__file__).resolve()` (a common
pattern for "find the ComfyUI root," since `.resolve()` follows symlinks)
saw the flat, unrelated Nix store path instead of the meaningful
`dataDir/custom_nodes/<repo>` one -- confirmed via two real crashes
(`ComfyUI-SAM3`, `ComfyUI-SAM3DBody`, both assuming a normal
git-clone-into-custom_nodes/ layout). A bind mount isn't a symlink to the
OS, so this fixes the whole class of bug generically, not just those two,
with no per-node patch needed -- verified directly (both nodes' own
`COMFYUI_DIR` computation resolves correctly now, tested by actually
running Python inside the sandbox against the mounted path).

The general mechanism (`extraBwrapArgs` on `mkFHSVenv`) lives in
`../self-hosted.nix`, not here -- any other FHS-based service (currently
just OpenWebUI) can reuse it the same way if it ever needs to make
something look like it's really at a given path rather than merely
symlinked to it.

**preStart still does real work**: bwrap binds *through* the real
`/home`, so every node's mount-point directory has to already exist as a
plain directory on the real host filesystem before the sandbox launches,
or the bind fails outright (confirmed: "No such file or directory").
`prepareNodeMountsScript` in `comfyui.nix` `mkdir -p`s one per
`installed.nodes` entry and removes any directory for a node no longer
declared, on every start. These host-side directories are always empty
placeholders -- the actual node source only ever appears inside the
sandbox's own mount namespace, nothing is ever written to the host disk
for this.

**Consequence**: node bind mounts are baked into the FHS sandbox
derivation at **rebuild time** (`nodeBindArgs` is computed from
`installed.nodes` when Nix evaluates), not adjustable by any running
action. Activating or deactivating a node is always rebuild + restart --
in practice this changes nothing you'd actually do differently: ComfyUI
itself only scans `custom_nodes/` once at its own startup, so a node
change always needed a restart anyway.

## The one patched node

`ComfyUI-post-processing-nodes` hardcodes `ImageFont.truetype("arial.ttf", ...)`.
The old bash relied on an Arch-specific hook symlinking system fonts into
`/usr/share/fonts/truetype`; here, `mkNodeSrc` in `comfyui.nix` instead
`sed`-patches that one line to a real `dejavu_fonts` store path at build
time. This is a genuine bug in the node's own source (a bad hardcoded
font lookup), not a path-resolution artifact of how nodes are mounted --
unlike the `COMFYUI_DIR` problem above, patching the source is the only
real fix, and only this one node needs it.

**Known remaining limitation**: `ComfyUI-SAM3DBody` also tries to copy an
FBX viewer asset into its own source directory (`SCRIPT_DIR / "web"`).
That's a genuine write, not a path-resolution issue, so the bind-mount
fix above doesn't touch it -- the source stays read-only on purpose
(reproducibility), confirmed the write still fails (EROFS) exactly as
before. Non-fatal (ComfyUI keeps running, only that node's FBX viewer
feature is affected) and not patched -- no verified-correct writable
location for that asset is known, and this project prefers leaving a
narrow, non-fatal limitation documented over guessing at a fix.

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
just not hash-verified) and installed with `pip install --no-deps` as
`venvEnsureScript`'s `extraSteps`, after the main hash-locked install.
`--no-deps` matters: their actual dependencies (torch, hydra-core,
omegaconf, iopath, ...) are already resolved and hash-locked by the main
install: letting pip re-resolve here could silently install a different
version than the one actually locked.

## Updating `requirements.lock`

`requirements.in` is **not** a checked-in file for ComfyUI -- unlike
OpenWebUI's, it depends on the *installed* nodes' own `requirements.txt`
content, and a hand-maintained second copy of that would just drift from
`nodes.nix`/`comfyui.nix` (the actual source of truth). It's a Nix
derivation instead (`comfyRequirementsIn` in `comfyui.nix`), built from
each `installed.nodes` entry's already-pinned source plus a small static
header (`comfyRequirementsInHeader`), with a handful of fixups baked in
(`ComfyUI-BrushNet`'s conflicting `accelerate` pin relaxed; the 4 git deps
above stripped out). Only currently-installed nodes are included --
toggling a node off also shrinks the dependency set that needs
resolving/locking.

The header pins torch/torchvision/torchaudio to plain stock-PyPI versions
(no `--extra-index-url`, no `+cuXXX` tag -- that scheme is obsolete for
this PyTorch generation, confirmed directly against PyPI's JSON API) plus
the exact matching CUDA dependency set (`cuda-toolkit`, `cuda-bindings`,
`nvidia-cudnn-cu13`, `nvidia-cusparselt-cu13`, `nvidia-nccl-cu13`,
`nvidia-nvshmem-cu13`, `triton`) copied verbatim from torch's own declared
`Requires-Dist`, rather than left for pip-compile to discover via
backtracking -- torch is pinned to the 2.11.0 generation specifically
because `torchaudio`'s last-ever PyPI release is 2.11.0 (confirmed by
reading its actual wheel's `METADATA`; it declares zero `Requires-Dist` of
its own, not even on `torch`, so it can never itself be the source of a
resolver conflict, but also can't be expected to work against a torch two
generations newer than the last one it ever shipped against).

`systemctl start self-hosted-comfyui@update:deps:apply` runs the whole
thing and writes the result: builds `comfyRequirementsIn`, runs
pip-compile (seeded from the current lock for speed -- see
`mkDepsUpdateScript` in `../self-hosted.nix`), diffs against the
checked-in lock, and if it differs, moves the new one straight into
`requirements.lock`. Use bare `@update:deps` first if you want to see the
diff (`requirements.lock.new` + `journalctl -u
self-hosted-comfyui@update:deps`) before committing to it. Same shape as
OpenWebUI's `@update`/`@update:apply`.

**Seeding caveat**: seeding from the current lock only helps when the
lock is already scheme-consistent with the new header -- if you're
changing something as fundamental as the CUDA/index scheme itself (like
the stock-PyPI rewrite above), the seed actively fights the resolver
(discarding one stale pin at a time instead of resolving cleanly) and an
unseeded run is faster despite resolving from scratch. Not the normal
case; only relevant for a scheme-level rewrite, not a routine bump.

Run it after adding/activating a node, bumping a node's pinned `rev`, or
bumping `coreRev` -- any of those can change what needs resolving.

Expect new conflicts occasionally -- the old bash's own comments document
at least one known node-vs-node version fight, and the accelerate/BrushNet
one above was found the same way: `pip-compile` just fails loudly with
exactly which two constraints disagree (visible in `journalctl`). Fix by
relaxing the losing side's constraint in the header or (if it's a node's
own `requirements.txt` that's the problem) adding a targeted `sed` fixup
next to the ones that already exist in `comfyRequirementsIn`
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
restart the service -- node mounts are baked into the sandbox at rebuild
time, so both steps are required (see "Node mounting" above). Activating
a node with its own `requirements.txt` also needs a `requirements.lock`
regeneration (above), or it'll be mounted but fail to import at runtime
-- the next restart's preStart will pick up the regenerated lock
automatically, no separate step needed beyond the regeneration itself.

**Drop a node from the catalog entirely**: remove it from both
`installed.nodes` and `nodeStore`. If it's only removed from
`installed.nodes`, it deactivates but stays pinned for later.

**Pin a new model into the catalog (not yet installed)**: append
`{ name, type, url, target }` to `config/self-hosted/comfyui/models.nix`
(`modelStore`). Costs nothing until it's in `installed.models`.

**Install/remove a pinned model from disk**: add/remove its `name` in
`installed.models` (`comfyui.nix`), rebuild, restart the service --
preStart's `syncModelsScript` handles both directions automatically on
that restart: newly-added names get fetched, newly-removed names get
their file deleted, in the same run. Shrinking `installed.models` and
restarting is fully reversible either way -- the pin stays in
`modelStore` regardless, only the file on disk comes and goes.

**Full teardown, including the real data**: there is no scripted action
for this, deliberately -- see `../docs/architecture.md`'s "No uninstall
action". The real `user/` vault content (workflows, prompts you've
saved) is precious and only ever removed by a deliberate, by-hand
`rm -rf`.

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
