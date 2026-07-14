# Decisions

## Assert vs. merge for shell/venv path collisions

Considered: letting a directory be both a declared shell and a declared
venv trigger, with both `.envrc` contents merged.

Rejected because it requires `shells.nix` and `venv.nix` to coordinate
on ownership of a single generated file (`<path>/.envrc`), which either
means one module reaching into the other's internals, or a third
"merge" module neither file's own logic lives in. Both break the
project's own rule that `default.nix` (and by extension, each module)
only concerns itself with its own directory.

Chosen instead: hard assertion at eval time. `venv.nix` flattens both
`vars.shells[*].path` and every venv's effective `activation.paths`,
intersects them, and fails the build with the exact colliding path(s) if
the intersection is non-empty. If you actually want both a toolchain
shell and a venv in the same directory, declare the venv's *interpreter*
inside the shell's own package list instead of layering a second
mechanism on top -- see `ARCHITECTURE.md`'s note in `README.md`'s config
example.

## source_env instead of a shared direnvrc

`shells.nix` already owns `home.file.".config/direnv/direnvrc"`. If
`venv.nix` wrote to the same key, two independent modules would be
generating conflicting content for one file -- a straightforward
home-manager build failure the moment both are non-empty.

Chosen: venv-specific direnv functions live in a separate file,
`~/.config/direnv/venvrc`, and every venv-generated `.envrc` starts with
`source_env ~/.config/direnv/venvrc` before calling `use venv_<name>`.
direnv supports arbitrary `source_env` calls inside an `.envrc`, so
there's no shared file for the two modules to fight over -- each stays
fully self-contained.

## Why the manifest path is hardcoded

The ask was a path relative to the venvs module's own directory
(`.../modules/packages/venvs` -> 4 levels up -> `Dotfiles/.store/venvs.json`).

That can't be a real nix path literal (`../../../../.store/venvs.json`)
for a subtle but important reason: any `./foo` or `../foo` path literal
inside a nix module, once evaluated as part of a flake, gets copied into
the immutable `/nix/store`. `toString` on that path then gives a store
path, not your live `~/Dotfiles` checkout -- and `venvs.json` needs to
be **read and written** at runtime by plain bash, which is impossible
against a read-only store path.

Chosen instead: `manifestPath = "${homeDir}/Dotfiles/.store/venvs.json"`,
built from `config.vars.homeDirectory` (the same value `shells.nix`
already uses for `~` expansion), not from a nix path literal. This is
the one deliberate exception to "always relative" in the whole module --
flagged here and inline in `venv.nix` specifically so it isn't mistaken
for an oversight later.

## Shim protocol (why activation can't just mutate the shell)

`venvctl activate <name>` runs as a child process. A child process
cannot change its parent shell's environment -- that's true regardless
of shell (bash, zsh, fish all work this way), so no amount of "just
export it in the script" can work.

Chosen: `venvctl activate`/`deactivate` print a tiny, shell-agnostic
`KEY=value` protocol to stdout and nothing else (diagnostics go to
stderr, so they never corrupt parsing):

```
VIRTUAL_ENV=<path>
PATH_PREPEND=<path>/bin
```

and, for deactivate, the sentinel `VIRTUAL_ENV=` (empty value) meaning
"clear it". A thin per-shell shim (`lib/shims/activate.fish`,
`activate.bash`) sources this output and applies it to the *current*
shell. This is the only shell-specific code in the entire system --
`venvctl` and everything under `lib/manage`, `lib/cli`, `lib/lock` stay
completely shell-agnostic, and adding support for a third shell later is
a ~15-line shim, not a rewrite.

## Why "latest" packages are never touched on rebuild

Auto-upgrading floating packages on every `home-manager switch` means a
routine, unrelated config change (e.g. editing an entirely different
module) can silently change what code runs in a venv, with no diff to
review and no way to pin a bad rebuild's outcome after the fact.

Chosen: `latest` packages are installed once, at first creation, and
`build.sh` (the rebuild path) explicitly skips any package already
present regardless of what "latest" would currently resolve to. The
*only* way a `latest` package changes version is `venvctl update <name>`
or `update all`, run deliberately, on purpose, separately from any
rebuild.

## Why `${./lib}` instead of per-file nix path interpolation

Each `${./lib/manage/build.sh}`-style interpolation copies that single
file into its own, independent nix store path -- `build.sh` would have
no reliable way to find `manifest.sh` or `log.sh` next to it at runtime,
since "next to it" stops meaning anything once each file is copied
separately.

Chosen: `venv.nix` copies the whole `./lib` subtree as one store path
(`libRoot`), exported as `$VENVCTL_LIBROOT`, and every script under
`lib/` sources its siblings via `"$VENVCTL_LIBROOT/manage/whatever.sh"`.
This is also why scripts don't use `dirname "${BASH_SOURCE[0]}"` for
self-location -- that would work too, but `$VENVCTL_LIBROOT` is one
explicit, greppable source of truth instead of N scripts each
re-deriving the same thing.
