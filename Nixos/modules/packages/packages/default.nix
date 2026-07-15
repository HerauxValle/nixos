{ lib, pkgs, ... }:

# Package declaration framework.
#
# This module defines the public schema for declarative package
# installation. Actual package declarations live in ./packages.nix and
# resolution into environment.systemPackages happens in ./config.nix.
#
# Package sources are arbitrary package sets (pkgs, pkgs.kdePackages,
# custom attrsets, etc.). `pkgs` is always available automatically via a
# mkDefault assignment; all other sources must be declared explicitly.

{
  imports = [
    ./config.nix
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
        Packages to install grouped by source. Every package entry is a
        submodule to allow future expansion (versions, channels,
        overrides, etc.) without changing the public API.
      '';

      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              version = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;

                description = ''
                  Reserved for future package version selection. Currently
                  unused.
                '';
              };
            };
          }
        )
      );
    };
  };

  config.vars.environment.sources.pkgs = lib.mkDefault pkgs;
}
