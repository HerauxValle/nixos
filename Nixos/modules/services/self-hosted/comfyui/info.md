# ComfyUI -- self-hosted module reference

Schema: `./default.nix`. Wiring: `./comfyui.nix`. Implementation detail
pieces: `./lib/{fhs,node-mounting,requirements,models-sync,update}.nix`.
Real values: `Nixos/config/self-hosted/comfyui/comfyui.nix`. Node/model/patch
catalogs: `Nixos/config/self-hosted/comfyui/catalog/{nodes,models,patches}.nix`.
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
| `enabled` | bool | `false` | Master switch. `true` = live service + actions exist and run. `false` = torn down automatically on the next rebuild (see "Full teardown" in "Workflows" below), not just absent. |
| `dataDir` | str | `~/Applications/Networking/ComfyUI` | Writable base. Holds `custom_nodes/` (bind mounts), `models/`, `user/` (via storage), `node_data/` (per-patched-node writable data, see "Node source patches" below), and is passed as ComfyUI's `--base-directory`. |
| `venvDir` | str | `~/.impure/python-venvs/self-hosted/comfyui` | Disposable, regenerated automatically by preStart's `venvEnsureScript` whenever `requirementsLock`'s hash changes. See "`~/.impure/`" below. |
| `autoStart` | bool | `true` | Currently `false` in this machine's real config. |
| `environment` | attrsOf str | `{ }` | Passthrough env, merged with the fixed `toolchainEnv` (CC/CXX/CUDA_HOME/TORCH_CUDA_ARCH_LIST/etc) and `WAS_CONFIG_DIR` (see "Node source patches" below), see `comfyui.nix`. |
| `storage` | listOf `{src,dest}` | `[ ]` | Currently one entry: `user` -> the SelfHosted vault. |
| `requireMounts` | listOf str | `[ ]` | Mountpoint check before preStart -- the SelfHosted vault. |
| `teardownPaths` | listOf str | `[ ]` | Paths, relative to `dataDir`, removed when `enabled = false`. **Non-empty here, deliberately** -- `["custom_nodes" "models"]` -- since `dataDir` also holds `output`/`temp`/`input` (real generated/uploaded content no `storage` entry covers), so the usual empty-default "everything but storage" teardown would destroy it. See `../docs/architecture.md`'s `mkTeardownActivationScript` section. |
| `coreRev` | str | *required* | Pinned `comfyanonymous/ComfyUI` git rev. |
| `coreHash` | str | *required* | `fetchFromGitHub` SRI hash for `coreRev`. |
| `nodeStore` | listOf `{owner,repo,rev,hash}` | `[ ]` | **Catalog** of every node ever pinned, whether or not currently active. `repo` also becomes the `custom_nodes/` directory name and the addressable key for `installed.nodes`. |
| `nodePatches` | listOf `{repo,script,dirs}` | `[ ]` | Per-node source patches and/or pre-created writable directories, keyed by `repo`. See "Node source patches" below. |
| `modelStore` | listOf `{name,type,url,target}` | `[ ]` | **Catalog** of every model ever pinned (~700GB across all of them). `type` is `hf`\|`civitai`\|`git`\|`url`. `target` is relative to `dataDir`. `name` is the addressable key for `installed.models` -- not required to be unique, entries sharing a name are one logical model split across files. |
| `installed.nodes` | listOf str | `[ ]` | `repo` values from `nodeStore` that actually get bind-mounted into `custom_nodes/`. Unknown name = hard eval-time error. |
| `installed.models` | listOf str | `[ ]` | `name` values from `modelStore` that preStart fetches and keeps on disk, removing anything backing a name no longer listed. Unknown name = hard eval-time error. |

**Store vs. installed**: `nodeStore`/`modelStore` (`./catalog/nodes.nix`, `./catalog/models.nix`) are
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

- `self-hosted-comfyui.service` -- the live process. `TimeoutStartSec=infinity`
  -- systemd's default 90s start timeout was killing a legitimately-long
  first-time venv install mid-download, causing a restart-and-partial-retry
  loop that never converged; confirmed via a real run, fixed generically for
  every service in this tree, not just ComfyUI. `preStart` runs, in order:
  `mkdir -p` for `output`/`temp`/`input` (--base-directory expects them to
  exist -- some Comfyroll nodes eagerly `os.listdir()` them before ComfyUI
  itself lazily creates them), the generated `node_data/<repo>` mkdir set
  for every active `nodePatches` entry (see "Node source patches" below),
  `prepareNodeMountsScript` (mkdir/rm the `custom_nodes/<repo>` mount-point
  directories to match `installed.nodes`, cheap, no network -- see "Node
  mounting" below, actual node content is bind-mounted in by the sandbox
  itself), `venvEnsureScript` (no-op unless `requirementsLock`'s hash
  changed since the last successful install), `syncModelsScript` (fetch
  every `installed.models` entry that's missing/corrupt/undersized, then
  remove any file under `dataDir/models/` not backing a current entry --
  both directions, every start).
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
`sed`-edit `config/self-hosted/comfyui/comfyui.nix` or `catalog/nodes.nix`
directly (deps writes `requirements.lock` directly, same as OpenWebUI's
`@update:apply`) -- still never rebuilds or restarts on their own, and
never needs a follow-up manual install either: the next restart's
preStart picks up the change automatically.

## `--base-directory` and `--database-url`

`main.py` runs straight from the read-only Nix store
(`comfyCore = fetchFromGitHub {...}`). ComfyUI's own `--base-directory`
flag (confirmed in `comfy/cli_args.py`, not assumed) redirects its
`models/`, `custom_nodes/`, `input/`, `output/`, `temp/`, `user/` lookups
at `dataDir` instead of wherever `main.py` lives -- this is what lets the
core source stay a plain immutable store path while still having writable
data. If a node writes into its *own* source directory (not `dataDir`),
that will fail (EROFS/read-only) -- see "Node source patches" below for
the (now nine) real, confirmed cases of this and how each is fixed.

`--database-url` is a second, separate flag needed on top of
`--base-directory` -- confirmed by reading `comfy/cli_args.py` directly:
the sqlite DB path (`comfyui.db`) is computed once, at argparse time, as
a plain `os.path.join` relative to `cli_args.py`'s own location
(comfyCore, read-only), and `--base-directory` never touches it
afterward (checked `main.py`'s `apply_custom_paths()`, which only
redirects models/output/input/user via `folder_paths`, nothing
database-related) -- a real ComfyUI core gap, not something
`--base-directory` was ever meant to cover. Pinned to
`sqlite:///dataDir/user/comfyui.db` -- `user/` is where ComfyUI defaults
to putting it anyway, and it's already a real, vault-backed `storage`
symlink, so the database naturally lands with the rest of ComfyUI's
actual user data.

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

## Node source patches (`nodePatches`, `config/self-hosted/comfyui/catalog/patches.nix`)

A real Nix option (`vars.selfHosted.comfyui.nodePatches`, `listOf
{repo, script, dirs}`), not hardcoded logic -- deliberately scoped to
ComfyUI only, not a shared `self-hosted.nix` concept, since no other
service has anything resembling "many pluggable third-party source
components with occasional per-component bugs" to patch. Each entry:

- `script` (optional, default `""`) -- a shell fragment run against a
  writable copy of that node's fetched source (`mkNodeSrc` in
  `lib/node-mounting.nix`, `cwd` unset, use `$out`) before it's
  bind-mounted in. Empty means the entry exists only for its `dirs`.
- `dirs` (optional, default `[ ]`) -- extra paths, relative to that
  node's own `dataDir/node_data/<repo>` directory, that must exist
  (possibly empty) before the node's code runs. Generates real
  `mkdir -p` entries in `preStart` automatically (see "systemd units"
  above) -- every entry's own `node_data/<repo>` base directory is
  always created too, regardless of `dirs`. Only patches for
  currently-*installed* nodes are ever applied or get a directory
  created (`comfyui.nix`'s `activeNodePatches`, filtered the same way
  `activeNodes`/`activeModels` are).

Every real fix currently in `patches.nix`, all found by actually running
the service and reading the real traceback, not guessed at up front --
each hardcodes a write "next to my own source file" (or, worse, next to
`__main__.__file__` -- comfyCore's own entry point), and both of those
are deliberately read-only:

- `ComfyUI-post-processing-nodes` -- hardcodes `ImageFont.truetype("arial.ttf", ...)`.
  `sed`-patched to a real `dejavu_fonts` store path.
- `ComfyUI_FizzNodes`, `ComfyUI-Gemini` -- both compute a web-extension
  install target relative to `__main__.__file__` (comfyCore). Redirected
  to `node_data/<repo>`; Gemini also needed `os.mkdir` -> `os.makedirs(...,
  exist_ok=True)` since the redirected target is more deeply nested than
  its old sibling-of-source location.
- `ComfyUI-Custom-Scripts`, `ComfyUI-WD14-Tagger` -- both bundle their own
  copy of a shared `pysssss.py` helper, but **not the same version** --
  confirmed by actually reading both, not assumed from the shared
  filename. Custom-Scripts' version writes a live `pysssss.json` copied
  from a bundled `pysssss.default.json` template -- only the write
  (`config_path`) is redirected, the template read stays at the real
  source, since redirecting `get_ext_dir()` itself wholesale (tried
  first) broke that read entirely. WD14-Tagger's version has no such
  write at all (`pysssss.json` there is a real bundled resource, not a
  template) -- its `pysssss.py` needs no patching beyond `get_comfy_dir()`
  (both nodes' write-only web-extension symlink target); its
  `wd14tagger.py` has its own separate write
  (`get_ext_dir("models", mkdir=True)`, for downloaded tagger models),
  redirected with its own declared `dirs`.
- `ComfyUI_UltimateSDUpscale` -- self-downloads a third-party dependency
  into `current_dir/repositories/ultimate_sd_upscale` on first run.
  `current_dir` redirected to `node_data/<repo>` (with `dirs` declaring
  the nested path, since `os.listdir()` on a missing dir raises outright).
  A **second**, initially-missed bug: `repositories/__init__.py` (a real
  file bundled in the node's own repo, not something the download
  creates) independently recomputes its own path via `__file__` and
  always finds the real bind-mounted source -- redirected too, to the
  same `node_data/<repo>/repositories` the download actually populates.
- `ComfyUI-Easy-Use` -- three `os.path.dirname(__file__)`-based write
  targets in `__init__.py` (`wildcards/`, `styles/`, `styles/samples/`),
  globally redirected since all three are genuine writes. A **second**,
  initially-missed bug: `py/config.py`'s `FOOOCUS_STYLES_DIR` computes
  the *same* conceptual "styles" location entirely independently (via
  `Path(__file__).parent.parent`), still pointing at the real,
  never-populated source even after the first fix -- redirected to the
  exact same `node_data/<repo>/styles`.
- `ComfyUI-Inspire-Pack` -- `resource_path` (read, stays at the real
  source: it also resolves a bundled `.example` template) vs.
  `pb_yaml_path` (write, the live preset file -- redirected). Caught
  internally either way (a bare `except`, not a crash) -- this only
  fixes the resulting "prompt builder preset" feature staying
  permanently empty, not a startup failure.
- `was-node-suite-comfyui` -- no source patch at all. Already supports
  overriding its config location via a `WAS_CONFIG_DIR` environment
  variable (its own default is its read-only bind mount) -- set directly
  in `comfyui.nix`'s `environment` instead. This entry in `patches.nix`
  exists purely for its `dirs`, to get `node_data/was-node-suite-comfyui`
  created in `preStart` before the node tries to write into it.

**Known remaining limitation, deliberately not patched**:
`ComfyUI-SAM3DBody`'s own `prestartup_script.py` tries to copy an FBX
viewer asset into its own source directory (`SCRIPT_DIR / "web"`) before
the node even gets to the point `nodePatches` could redirect anything --
confirmed the write still fails (EROFS) exactly as before. Non-fatal
(ComfyUI keeps running, only that node's FBX viewer feature is affected)
and not patched -- no verified-correct writable location for that asset
is known, and this project prefers leaving a narrow, non-fatal limitation
documented over guessing at a fix.

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
`catalog/nodes.nix`/`comfyui.nix` (the actual source of truth). It's a Nix
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
`config/self-hosted/comfyui/catalog/nodes.nix` (`nodeStore`). It sits there,
pinned but inert, until added to `installed.nodes`.

**Check/bump a pinned node's commit**: `systemctl start
self-hosted-comfyui@update:nodes:<repo>` (any `nodeStore` entry, active
or not) prints the new `rev`/`hash` if one exists
(`journalctl -u self-hosted-comfyui@update:nodes:<repo>`).
`@update:nodes:<repo>:apply` does the same check and `sed`-writes the new
`rev`/`hash` into that exact entry in `catalog/nodes.nix` directly.
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
`{ name, type, url, target }` to `config/self-hosted/comfyui/catalog/models.nix`
(`modelStore`). Costs nothing until it's in `installed.models`.

**Install/remove a pinned model from disk**: add/remove its `name` in
`installed.models` (`comfyui.nix`), rebuild, restart the service --
preStart's `syncModelsScript` handles both directions automatically on
that restart: newly-added names get fetched, newly-removed names get
their file deleted, in the same run. Shrinking `installed.models` and
restarting is fully reversible either way -- the pin stays in
`modelStore` regardless, only the file on disk comes and goes.

**Full teardown (reconcilable parts only)**: set `enabled = false` in
`config/self-hosted/comfyui/comfyui.nix`, rebuild -- `mkTeardownActivationScript`
(`../self-hosted.nix`) removes exactly `custom_nodes/`, `models/`, and
`venvDir` automatically, as part of that same rebuild's activation
(`teardownPaths = ["custom_nodes" "models"]`, see the Options table
above). `output/`, `temp/`, `input/`, `node_data/`, and the real `user/`
vault content (workflows, prompts you've saved) are **never** touched by
this -- only a deliberate, by-hand `rm -rf` removes those. Flip `enabled`
back to `true` and rebuild again to reinstall nodes/models/venv from the
same declared config.

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
