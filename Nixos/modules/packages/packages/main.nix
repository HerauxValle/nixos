{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

# Resolves declared packages (with optional multi-version coexistence)
# into environment.systemPackages. The actual per-package logic lives
# in ./lib so this file stays a thin driver.
#
# `inputs` and `system` must be supplied via specialArgs in flake.nix.
# They're only touched by version specs that name a flake input or a
# raw commit/channel string — see ./docs/README.

let
  inherit (config.vars.environment) sources packages;

  helpers = import ./lib {
    inherit lib pkgs inputs;
    system = pkgs.system;
  };

  resolvedPackages = lib.flatten (
    lib.mapAttrsToList (
      sourceName: packageSet:

      let
        source = sources.${sourceName} or (throw "Unknown package source '${sourceName}'.");
      in

      lib.mapAttrsToList (
        packageName: pkgCfg:

        if pkgCfg.versions == { } then
          helpers.resolveDefault { inherit sourceName packageName source; }
        else
          helpers.resolveVersions {
            inherit sourceName packageName source;
            inherit (pkgCfg) versions default;
          }

      ) packageSet

    ) packages
  );
in
{
  environment.systemPackages = resolvedPackages;
}
