# &desc: "Package helper functions aggregator -- wires up resolve/validate/wrap utilities for main.nix package resolution."

{
  lib,
  pkgs,
  inputs,
  system,
}:

# Aggregates the packages/lib helper functions for use by main.nix.

rec {
  wrapSuffixed = import ./wrap-suffixed.nix { inherit pkgs; };

  wrapAliased = import ./wrap-aliased.nix { inherit pkgs; };

  validate = import ./validate.nix { inherit lib; };

  resolveSpec = import ./resolve-spec.nix { inherit inputs system lib; };

  resolveDefault = import ./resolve-default.nix { };

  resolveVersions = import ./resolve-versions.nix {
    inherit lib wrapSuffixed wrapAliased validate resolveSpec;
  };
}
