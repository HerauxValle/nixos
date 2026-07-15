{ lib, pkgs }:

# Aggregates the packages/lib helper functions for use by main.nix.

rec {
  wrapSuffixed = import ./wrap-suffixed.nix { inherit pkgs; };

  validate = import ./validate.nix { inherit lib; };

  resolveDefault = import ./resolve-default.nix { };

  resolveVersions = import ./resolve-versions.nix {
    inherit wrapSuffixed validate;
  };
}
