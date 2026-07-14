# Caveats

Cross-cutting notes on the shells.nix/venv.nix coupling and the
per-shim differences introduced while wiring up matching load/unload
banners. Read this before touching either module's direnv wiring, or
adding a fifth shim.

## shells.nix and venv.nix now share one file on purpose

`~/.envrc` (the $HOME anchor) is owned by `shells.nix`, but its
_content_ now calls into both modules:
