<!-- &desc: "Venv module architecture documentation -- directory layout, data flow, mutable state handling, direnv/venvctl mechanisms." -->

# Architecture

## Layout

```
venvs/
  default.nix           imports + options.vars.venvs (schema only)
  venv.nix              path resolution, assertion, direnv wiring,
                         home.activation entries, venvctl derivation
  lib/
    manage/
      log.sh             logLevel-aware print helpers
      manifest.sh         read/write/diff venvs.json
      build.sh             ensure one venv exists, sync pinned pkgs
      update.sh            bump "latest"-pinned pkgs on demand
      remove.sh             delete a venv dropped from config
      sync.sh                orchestrator: build all, then prune stale
    lock/
      lockfile.sh        optional `pip freeze` writer (only if
                          venv.lockfile = true)
    cli/
      cli.sh             venvctl subcommand dispatcher
      activate.sh         resolve name/path -> neutral protocol
      deactivate.sh        emit the "clear" sentinel
      list.sh               human-readable venv listing
    shims/
      activate.fish      fish functions consuming the protocol
      activate.bash        bash/zsh equivalent, unused today
  docs/
    README.md
    ARCHITECTURE.md      (this file)
    DECISIONS.md
```

Every file stays under ~150 lines by design -- each does exactly one
thing, and composition happens by sourcing/calling, not by growing any
single file into a mega-script.

## Why venv.nix isn't a copy of shells.nix's shape

`shells.nix` only ever writes **pure, static** files: `.envrc` content
and `direnvrc` are both fully determined by the nix config at eval time,
so home-manager's normal file-generation-and-symlink model is sufficient
-- add an entry, a new `.envrc` appears; remove one, home-manager's own
generation diffing removes the symlink.

Venvs have real mutable state on disk (an actual Python interpreter, `.dist-info`
directories, pip's internal bookkeeping) that home-manager's declarative
file management has no visibility into. That's the entire reason
`lib/manage/` exists: `venvs.json` is a hand-rolled generation-diff,
playing the role home-manager's own state tracking plays for `home.file`,
but scoped to directories nix doesn't actually own the contents of.

## Data flow on rebuild

```
home-manager switch
  -> home.activation.allowDeclarativeVenvs   (direnv allow, after linkGeneration)
  -> home.activation.buildDeclarativeVenvs   (after allow)
       -> lib/manage/sync.sh
            -> lib/manage/build.sh   (once per declared venv)
                 -> lib/manage/manifest.sh   (read prev state)
                 -> pip install/reinstall as needed
                 -> lib/lock/lockfile.sh     (if lockfile = true)
                 -> lib/manage/manifest.sh   (write new state)
            -> lib/manage/remove.sh  (once per manifest-only stale entry)
```

`venvctl` (the interactive CLI) reuses `lib/manage/update.sh` and
`lib/manage/manifest.sh` directly -- it is not a separate reimplementation
of the sync logic, just a different entry point into the same scripts.

## Data flow on `cd` into a trigger dir

```
direnv (via .envrc) -> source_env ~/.config/direnv/venvrc
                     -> use venv_<name>
                          -> export VIRTUAL_ENV, PATH_add <path>/bin
                          -> prints entry banner
```

This never goes through `venvctl` at all -- direnv's own function-call
mechanism handles activation for the `onEntry` case. `venvctl
activate`/`deactivate` + the shims are a *separate* path, for activating
a venv manually outside of any direnv-tracked directory.

## Why two independent activation mechanisms exist

- **direnv path** (`onEntry` + `activation.paths`): automatic, tied to
  `cd`, matches how `shells.nix` already works, zero extra typing.
- **venvctl + shim path**: for venvs with no `activation.paths` at all,
  or for activating one manually regardless of your current directory
  (e.g. a venv whose only declared paths are elsewhere).

They're deliberately decoupled -- direnv's `venvrc` functions don't call
into `venvctl`, and `venvctl activate` doesn't touch direnv state. Each
is a complete, independent way to end up with the same
`VIRTUAL_ENV`/`PATH` result.
