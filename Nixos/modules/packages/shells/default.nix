{ lib, ... }:

# Schema only (empty default -- an always-valid, always-safe fallback).
# No generic entry makes sense here, unlike scripts/default.nix's pacnix --
# which per-directory shells you want is entirely personal. See
# Nixos/config/shells.nix for the actual list. Direnv-generation logic
# that consumes this lives in ./shells.nix, imported below.
{
  imports = [ ./shells.nix ];

  options.vars.shells = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = [ ];
    description = "Per-directory declarative shells: path, packages on PATH there, and whether that's recursive.";
  };
}
