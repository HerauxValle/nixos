# venvs/

Declarative Python virtualenvs, sibling module to `../shells/`. Declare
venvs in nix, they get built/pruned on `home-manager switch`, and
optionally auto-activate via direnv when you `cd` into a trigger dir.

## Quick config example

```nix
vars.venvs = {
  logLevel = "error";
  basePath = "~/.impure/python-venvs/nix-declared";

  venvs = {
    scraper = {
      python = "python311";
      packages = {
        requests = "2.32.3";
        beautifulsoup4 = "latest";
      };
      activation.onEntry = true; # implicit trigger: basePath/scraper
      lockfile = true;
    };

    dataproj = {
      path = "~/dev/dataproj/.venv";
      packages = { pandas = "2.2.2"; };
      activation = {
        onEntry = true;
        paths = {
          "~/dev/dataproj" = "recursive";
        };
      };
    };
  };
};
```

## What happens on rebuild

1. Each declared venv is created (if missing) and its **pinned**
   packages are installed/reinstalled to match the declared version.
2. Packages pinned to `"latest"` are installed once, on first creation,
   and then left alone -- rebuild never silently upgrades them.
3. Venvs present in the state manifest but no longer declared are
   deleted.
4. `.envrc` files are (re)written for every `activation.paths` entry,
   pointing at `~/.config/direnv/venvrc`.

## venvctl

Installed on `$PATH` via `home.packages`.

```
venvctl list                 # show all declared venvs + build state
venvctl update <name|all>    # bump only "latest"-pinned packages
```

`venvctl activate` / `venvctl deactivate` exist but aren't meant to be
run bare -- a subprocess can't mutate your shell's environment. Source
the shim instead:

```fish
# in config.fish
source ~/Dotfiles/Nixos/modules/packages/venvs/lib/shims/activate.fish
```

then:

```fish
venv-activate scraper
venv-deactivate
```

(A bash/zsh equivalent ships in `lib/shims/activate.bash` for parity,
unused today.)

## A path can't be both a shell and a venv trigger

If a directory appears in both `vars.shells` and any venv's
`activation.paths`, the build fails at eval time with the exact
colliding path(s). See `docs/DECISIONS.md`.

## Further reading

- `ARCHITECTURE.md` -- directory layout, data flow, why it's split how it's split
- `DECISIONS.md` -- specific design calls and the reasoning behind each
