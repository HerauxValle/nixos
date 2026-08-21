# &desc: "Package resolution driver -- flattens sources + version specs into environment.systemPackages, supports multi-version coexistence via helpers in ./lib."

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
# raw commit/channel string -- see ./docs/README.

let
  inherit (config.vars.packages.environment) sources packages;

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

        # config.vars.isoBuild switches this whole list into allowlist
        # mode -- see ../../iso.nix and each package entry's own
        # `builtIn` option. False on the real machine, so this is a
        # no-op there.
        if config.vars.isoBuild && !pkgCfg.builtIn then
          {
            drvs = [ ];
            manifestEntries = [ ];
            aliasNames = [ ];
          }
        else if pkgCfg.versions == { } then
          {
            drvs = [ (helpers.resolveDefault { inherit sourceName packageName source; }) ];
            manifestEntries = [ ];
            aliasNames = [ ];
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

  allAliasNames = lib.flatten (map (r: r.aliasNames) resolved);

  duplicateAliasNames = lib.unique (
    lib.filter (name: lib.count (n: n == name) allAliasNames > 1) allAliasNames
  );
in
{
  # A top-level `assert` here (like lib/validate.nix's, which is safe --
  # it's a plain function, only forced when `resolved` above is read)
  # would instead gate this ENTIRE module's returned attrset, forcing
  # `packages` (and everything under it) strictly before the module
  # system can even structurally inspect the output -- broke the
  # laziness the config fixed-point relies on and caused a genuine
  # infinite recursion in practice. `assertions` is the actual NixOS
  # mechanism for this: lazy, checked only after config resolves.
  assertions = [
    {
      assertion = duplicateAliasNames == [ ];
      message =
        "Duplicate package alias(es) declared across config.vars.packages.environment.packages: "
        + lib.concatStringsSep ", " duplicateAliasNames
        + ". Alias names (the \"@<alias>\" part of a versions key) must be globally unique.";
    }
  ];

  environment.systemPackages = lib.flatten (map (r: r.drvs) resolved);

  environment.etc."packages-hash-manifest.json".source = manifestFile;

  # Discovers real hashes for bare-"#" (unpinned-on-purpose) package specs.
  # Only runs post-build, and only ever has entries to report when the
  # build itself already succeeded impurely -- see resolve-spec.nix for
  # why this can't happen at eval time (Nix's own fetch errors can't be
  # caught and reformatted from inside the expression language).
  system.activationScripts.packagesHashDiscovery = {
    deps = [ "etc" ];
    text = ''
      manifest="/etc/packages-hash-manifest.json"
      if [ -s "$manifest" ] && [ "$(${lib.getExe pkgs.jq} 'length' "$manifest")" -gt 0 ]; then
        red=$(printf '\033[31m')
        reset=$(printf '\033[0m')
        ${lib.getExe pkgs.jq} -c '.[]' "$manifest" | while IFS= read -r entry; do
          name=$(printf '%s' "$entry" | ${lib.getExe pkgs.jq} -r '.name')
          version=$(printf '%s' "$entry" | ${lib.getExe pkgs.jq} -r '.version')
          sourcePath=$(printf '%s' "$entry" | ${lib.getExe pkgs.jq} -r '.sourcePath')
          hash=$(${lib.getExe' pkgs.nix "nix"} hash path "$sourcePath" 2>/dev/null) || hash="<failed to hash '$sourcePath'>"
          echo "$red[Packages] Missing hash: $name $version $hash$reset"
        done
      fi
    '';
  };
}
