# Adding a new self-hosted service

Read `docs/architecture.md` first if you haven't -- this assumes you
know what `mkSelfHostedService`/`mkActionService`/etc. actually do.

## Decision tree

Answer these before writing anything. They determine which existing
service is the closest template.

1. **Does it ship a binary/release asset you can pin directly (GitHub
   releases, etc.), or does it need `pip install`?**
   - Binary -> write a `package.nix` (see Ollama's or Stash's -- pinned
     `version`+`hash`, `pkgs.fetchurl` + `pkgs.stdenv.mkDerivation` or
     `mkDerivationNoCC`). No venv, no FHS sandbox needed.
   - Python/pip -> you need `fhs.nix` (`mkFHSVenv`) + a hash-locked
     `requirements.lock`. See OpenWebUI for the simple case, ComfyUI for
     the "lock depends on dynamically-selected sources" case.
2. **Does it have a declarative list of *things* to reconcile** (models,
   plugins, nodes -- anything the service should fetch/maintain based on
   config rather than you clicking around a UI)?
   - No -> nothing to add (see Stash -- no reconciliation logic at all).
   - Yes, and reconciliation can happen before the process starts (pure
     filesystem work: fetch/remove files) -> a `preStart` step, no
     manual action (see ComfyUI's node/model reconciliation).
   - Yes, but reconciliation can only happen through the *live* process's
     own interface (an HTTP API that isn't up until the process has
     actually forked) -> a `postStart` step with its own
     poll-until-ready loop first (see Ollama's `sync.nix`).
   - Either way: if the full catalog is small/always-wanted-together, a
     flat typed list is enough (see Ollama's `models = listOf str`). If
     the catalog is much bigger than what's ever wanted installed at
     once, you need the store/installed split (see ComfyUI's
     `nodeStore`/`installed.nodes`). Don't reach for the store/installed
     split by default -- see `docs/conventions.md`.
3. **Does its real data need to live somewhere externally-mounted** (a
   Casket vault, a separate drive)?
   - Yes -> a `storage` entry + `requireMounts`, and `ensureDataDir = false`
     (see Stash/OpenWebUI/ComfyUI's `dataDir`/`storage` split).
   - No -> `dataDir` can be plain, `ensureDataDir = true` is safe (see
     Ollama).
4. **Does it need a real secret** (an API token, not a login password)?
   - Yes -> `environmentFile`, document the exact keys `secrets
     self-hosted <name>` should write in this service's `info.md`.
5. **Can its version be checked automatically** (a GitHub releases API,
   a default-branch HEAD)?
   - Yes -> write `update.nix`, wire `update`/`update:apply` actions.
     This should be true for almost everything -- see "Update" below.

## Files to create

```
Nixos/modules/services/self-hosted/<name>/
  default.nix   -- schema (options), imports ./<name>.nix
  <name>.nix    -- wiring: calls mkSelfHostedService + mkActionService
  package.nix   -- ONLY if it's a pinned binary fetch (plain function,
                   NOT in default.nix's imports -- see the pitfall below)
  fhs.nix       -- ONLY if it needs a venv (plain function, same pitfall)
  sync.nix      -- ONLY if reconciliation logic is nontrivial enough to
                   split out (Ollama's shape -- optional, can stay
                   inline in <name>.nix like Stash/OpenWebUI do)
  update.nix    -- the update check(s), plain function returning a
                   string or (ComfyUI-style) an attrset of actions
  info.md       -- dense reference: options table, action list, add/
                   remove/update workflows. Every existing service has
                   one -- read a couple before writing yours.

Nixos/config/self-hosted/
  <name>.nix    -- real values only (or <name>/ if the value count needs
                   splitting into multiple files, like ComfyUI's)
```

Then:
- Add `./<name>` to `modules/services/self-hosted/default.nix`'s `imports`.
- Add `./<name>.nix` (or `./<name>` for a folder) to
  `config/self-hosted/default.nix`'s `imports`.

## The `imports` pitfall

`default.nix` imports `./<name>.nix` (the wiring module) but must
**never** import `./fhs.nix` or `./package.nix` -- those are plain
functions (`{ pkgs }: ...` / `{ pkgs }: { version, hash }: ...`), not
NixOS modules. Importing one as a module fails with something like
"called with unexpected argument 'inputs'". This has bitten this repo
twice already (OpenWebUI, then almost ComfyUI) -- if you add a new plain
function file, double check it's referenced via `import ./foo.nix
{ ... }` from inside `<name>.nix`, never listed in `default.nix`'s
`imports`.

## Minimal example -- follow Stash

Stash is the simplest real service in this tree (pure binary fetch, one
`storage` entry, no reconciliation) -- the best starting template if
your new service doesn't need a venv or a declarative fetch list.

1. `package.nix`: pin `version`/`hash`, `fetchurl` the release asset,
   `installPhase` copies it to `$out/bin`.
2. `default.nix`: `enable`, `dataDir`, `autoStart`, `host`/`port` (if
   applicable), `version`/`hash`, `environment`, `storage`,
   `requireMounts`. Copy Stash's option descriptions and adjust.
3. `<name>.nix`: `execStart = "${package}/bin/<binary> --host ... --port ..."`,
   `mkSelfHostedService` with `ensureDataDir = true` if `dataDir` isn't
   externally gated, `mkActionService` with just `update`/`update:apply`
   (see "Wiring the generic actions" below -- there's nothing else to
   wire for a service with no reconciliation logic).
4. `update.nix`: same shape as `ollama/update.nix`/`stash/update.nix` --
   query the GitHub releases API, `nix-prefetch-url` + `nix hash convert`
   for the hash, print or (`apply = true`) `sed`-write into the real
   `config/self-hosted/<name>.nix` path (**plain string**, not a Nix
   path -- see architecture.md's `mkDepsUpdateScript` note, same
   reasoning applies here).
5. `info.md`: options table, action list, workflows. Copy Stash's
   structure.

## If it needs a venv

Follow OpenWebUI, not ComfyUI, unless the dependency list genuinely
needs to be assembled from dynamically-selected sources (multiple
plugin/node repos each with their own `requirements.txt`) the way
ComfyUI's does.

1. `fhs.nix`: `mkFHSVenv { name; targetPkgs = pkgs: with pkgs; [ pythonXXX ... ]; }`.
   Only include what compiled wheels actually need (check the upstream
   project's own install docs) -- don't copy ComfyUI's CUDA-heavy list
   wholesale for something that doesn't need a GPU.
2. Write `requirements.in` by hand (OpenWebUI's is a short, static,
   checked-in file -- `Python/locks/self-hosted/<name>/requirements.in`).
   Generate the first `requirements.lock` manually:
   ```
   nix-shell -p python312 python312Packages.pip-tools --run \
     "pip-compile --generate-hashes --allow-unsafe --resolver=backtracking \
       --output-file=requirements.lock requirements.in"
   ```
   `--allow-unsafe` matters -- without it, `setuptools` (and similar)
   end up unpinned, which `--require-hashes` then rejects at install
   time.
3. `<name>.nix`: `venvEnsureScript = selfHosted.mkVenvEnsureScript { fhsEnv; venvDir = cfg.venvDir; requirementsLock = ../../../../../Python/locks/self-hosted/<name>/requirements.lock; }`,
   added to `mkSelfHostedService`'s `preStart` list -- **not** wired into
   `mkActionService`'s `actions`, there's no manual install step anymore.
   `execStart` runs inside the FHS sandbox too, not just preStart --
   compiled wheels need the real `/lib`,`/usr/lib` on every import, not
   just once. `venvDir`'s default should be
   `${homeDirectory}/.impure/python-venvs/self-hosted/<name>` (see
   architecture.md's `~/.impure/` section) -- not under `dataDir`.
4. `update.nix`: thin wrapper around `selfHosted.mkDepsUpdateScript`
   (see `openwebui/update.nix` -- it's ~10 lines).

## Wiring the generic actions every service gets

There is exactly one action family every service gets:
`update`/`update:apply` (see "Update" below) -- checking upstream for
something newer, which genuinely needs live network access and can't
happen inside `nixos-rebuild`'s pure eval. Nothing else belongs in
`actions` by default:

```nix
actions = {
  update = updateScript;
  "update:apply" = updateApplyScript;
};
```

Everything that used to be a manual action (install, sync, uninstall) is
gone as a category, not just narrowed:
- **Install/reconcile** -> a `preStart` (or `postStart`, see the decision
  tree above) step on `mkSelfHostedService`, driven automatically by
  declared config on every service start. Nothing to wire into
  `mkActionService` at all.
- **Uninstall** -> doesn't exist. See architecture.md's "No uninstall
  action" and conventions.md's "Destructive vs. recoverable" for why --
  short version: everything it used to do is either already automatic, or
  was never safe to script once `dataDir` can hold genuinely precious,
  non-reconcilable content.

If your new service's `update.nix` needs more than one check (a pinned
binary/source *and* declarative deps, ComfyUI's shape), that's still just
more keys in the same flat `actions` attrset -- see "Update" below.

## Update

Every service should get `update`/`update:apply`, even the simplest
ones -- it's cheap (a GitHub API check + a hash prefetch, or a
pip-compile diff) and it's the one place "is there something newer"
lives, instead of you remembering to manually check upstream. See
`ollama/update.nix` (binary release check) or `openwebui/update.nix`
(deps check) for the two shapes this takes. If the service has *both* a
pinned binary/source *and* declarative deps (ComfyUI's shape), look at
`comfyui/lib/update.nix` for how to compose multiple checks under one
`update` (bare) action while keeping each individually addressable.

## Verify before calling it done

- `nixos-rebuild dry-build --flake ~/Dotfiles#herauxvalle` -- confirms
  the module evaluates. Not sufficient on its own.
- `nix-store --realize` the actual generated dispatch/action/preStart
  script paths (`grep` the dry-build output for `-dispatch.drv`,
  `-preStart-*.drv`, `-update.drv`, etc.) and read the resulting script
  content --
  confirms Nix string interpolation/escaping actually produced correct
  bash, not just that Nix accepted the syntax. This has caught real bugs
  every single time it's been done in this repo (a wrong sed pattern, a
  string-context path bug, an off-by-one in generated case branches) --
  don't skip it.
- For anything that writes to a real file (an `:apply` action, a
  `preStart` reconciliation script): test the actual write logic against
  a **throwaway copy** of the target file first, never the real one, and
  `diff` before/after to confirm exactly one thing changed. Every
  `:apply`/`sed` script in this system was verified this way before
  being trusted.
- If it does real network I/O (an update check, a sync fetch): run it
  for real at least once (`nix-shell -p <needed packages> --run "bash
  <the realized script path>"`) rather than trusting the script *looks*
  right. Several real bugs in this system (a wrong nix-prefetch-git JSON
  field, a missing `--type` flag, an actually-wrong pinned hash) were
  only caught this way.
