{
  lib,
  pkgs,
  inputs,
  system,
}:

# Aggregates the packages/lib helper functions for use by main.nix.

rec {
  wrapSuffixed = import ./wrap-suffixed.nix { inherit pkgs; };

  validate = import ./validate.nix { inherit lib; };

  resolveSpec = import ./resolve-spec.nix { inherit inputs system; };

  resolveDefault = import ./resolve-default.nix { };

  resolveVersions = import ./resolve-versions.nix {
    inherit lib wrapSuffixed validate resolveSpec;
  };
}
