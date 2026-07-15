{ lib, config, ... }:

let
  inherit (config.vars.environment) sources packages;

  resolvedPackages = lib.flatten (
    lib.mapAttrsToList (
      sourceName: packageSet:

      let
        source = sources.${sourceName} or (throw "Unknown package source '${sourceName}'.");
      in

      lib.mapAttrsToList (
        packageName: _:

        source.${packageName} or (throw ''
          Package '${packageName}' does not exist in source '${sourceName}'.
        '')

      ) packageSet

    ) packages
  );
in
{
  environment.systemPackages = resolvedPackages;
}
