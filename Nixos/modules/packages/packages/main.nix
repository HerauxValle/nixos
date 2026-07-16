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
    system = pkgs.stdenv.hostPlatform.system;
  };

  resolved = lib.flatten (
    lib.mapAttrsToList (
      sourceName: packageSet:

      let
        source = sources.${sourceName} or (throw "Unknown package source '${sourceName}'.");
      in

      lib.mapAttrsToList (
        packageName: pkgCfg:

        if pkgCfg.versions == { } then
          {
            drvs = [ (helpers.resolveDefault { inherit sourceName packageName source; }) ];
            manifestEntries = [ ];
          }
        else
          helpers.resolveVersions {
            inherit sourceName packageName source;
            inherit (pkgCfg) versions default;
          }

      ) packageSet

    ) packages
  );

  manifestEntries = lib.unique (lib.flatten (map (r: r.manifestEntries) resolved));

  manifestFile = pkgs.writeText "packages-hash-manifest.json" (builtins.toJSON manifestEntries);
in
{
  environment.systemPackages = lib.flatten (map (r: r.drvs) resolved);

  environment.etc."packages-hash-manifest.json".source = manifestFile;

  # Discovers real hashes for bare-"#" (unpinned-on-purpose) package specs.
  # Only runs post-build, and only ever has entries to report when the
  # build itself already succeeded impurely — see resolve-spec.nix for
  # why this can't happen at eval time (Nix's own fetch errors can't be
  # caught and reformatted from inside the expression language).
  system.activationScripts.packagesHashDiscovery = {
    deps = [ "etc" ];
    text = ''
      manifest="/etc/packages-hash-manifest.json"
      if [ -s "$manifest" ] && [ "$(${lib.getExe pkgs.jq} 'length' "$manifest")" -gt 0 ]; then
        ${lib.getExe pkgs.jq} -c '.[]' "$manifest" | while IFS= read -r entry; do
          name=$(printf '%s' "$entry" | ${lib.getExe pkgs.jq} -r '.name')
          version=$(printf '%s' "$entry" | ${lib.getExe pkgs.jq} -r '.version')
          spec=$(printf '%s' "$entry" | ${lib.getExe pkgs.jq} -r '.spec')
          sourcePath=$(printf '%s' "$entry" | ${lib.getExe pkgs.jq} -r '.sourcePath')
          hash=$(${lib.getExe' pkgs.nix "nix"} hash path "$sourcePath" 2>/dev/null) || hash="<failed to hash '$sourcePath'>"
          echo "[Packages] Missing hash: $name $version $hash  (spec '$spec')"
        done
      fi
    '';
  };
}
