{
  lib,
  pkgs,
  config,
  ...
}:

# Resolves declared packages (with optional multi-version coexistence)
# into environment.systemPackages. Renamed from config.nix; the actual
# per-package logic lives in ./lib so this file stays a thin driver.

let
  inherit (config.vars.environment) sources packages versionOverrides;

  helpers = import ./lib { inherit lib pkgs; };

  resolvedPackages = lib.flatten (
    lib.mapAttrsToList (
      sourceName: packageSet:

      let
        source = sources.${sourceName} or (throw "Unknown package source '${sourceName}'.");
      in

      lib.mapAttrsToList (
        packageName: pkgCfg:

        if pkgCfg.versions == [ ] then
          helpers.resolveDefault { inherit sourceName packageName source; }
        else
          helpers.resolveVersions {
            inherit
              sourceName
              packageName
              source
              versionOverrides
              ;
            inherit (pkgCfg) versions default;
          }

      ) packageSet

    ) packages
  );
in
{
  environment.systemPackages = resolvedPackages;
}
