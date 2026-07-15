{ lib, pkgs, ... }:

# Package declaration framework.
#
# This module defines the public schema for declarative package
# installation. Actual package declarations live in your own
# packages.nix; resolution into environment.systemPackages happens in
# ./main.nix, using the helpers in ./lib.
#
# Package sources are arbitrary package sets (pkgs, pkgs.kdePackages,
# custom attrsets, etc.). `pkgs` is always available automatically via a
# mkDefault assignment; all other sources must be declared explicitly.

{
  imports = [
    ./main.nix
  ];

  options.vars.environment = {
    sources = lib.mkOption {
      default = { };

      description = ''
        Named package sources. Each source is an attribute set exposing
        packages by name (e.g. pkgs.kdePackages, python package sets or
        custom package collections).
      '';

      type = lib.types.attrsOf lib.types.raw;
    };

    packages = lib.mkOption {
      default = { };

      description = ''
        Packages to install grouped by source. Each entry may optionally
        declare multiple coexisting versions via `versions`/`default`
        (see docs/versions.txt for the full model).
      '';

      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              versions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];

                description = ''
                  Version strings to install side-by-side, each exposed
                  with its binaries suffixed (e.g. "swift-5.9.4").
                  "latest" is a valid literal entry meaning "whatever
                  `sources` currently provides". Leave empty (the
                  default) for plain, unsuffixed installation identical
                  to a package with no versioning at all.
                '';
              };

              default = lib.mkOption {
                type = lib.types.str;
                default = "latest";

                description = ''
                  Which entry in `versions` is additionally exposed
                  unsuffixed on PATH. Must be a member of `versions`
                  when `versions` is non-empty; ignored (and never
                  checked) when `versions` is empty.
                '';
              };
            };
          }
        )
      );
    };

    versionOverrides = lib.mkOption {
      default = { };

      description = ''
        Sparse pinned-derivation overrides, keyed as
        sourceName -> packageName -> version -> derivation. Only needed
        for version strings other than "latest", typically pulled from
        a separately pinned nixpkgs flake input.
      '';

      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.attrsOf lib.types.raw));
    };
  };

  config.vars.environment.sources.pkgs = lib.mkDefault pkgs;
}
