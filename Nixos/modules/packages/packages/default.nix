{ lib, pkgs, ... }:

# Package declaration framework.
#
# This module defines the public schema for declarative package
# installation. Resolution into environment.systemPackages happens in
# ./main.nix, with per-package logic in ./lib. See ./docs/README for
# the full versioning model.

{
  imports = [ ./main.nix ];

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
        Packages to install, grouped by source. See ./docs/README for
        the full versioning model.
      '';

      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              versions = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };

                description = ''
                  Named versions for this package, mapping a version
                  label to a source spec string:
                    ""/"latest"     -> the package from `sources.<name>`
                    <flake input>   -> resolved from that flake input
                    <commit/channel> -> fetched on the fly (needs --impure)
                  Leave as `{ }` (the default) for the plain, unsuffixed
                  package with no version handling.
                '';
              };

              default = lib.mkOption {
                type = lib.types.str;
                default = "latest";

                description = ''
                  Which key in `versions` is exposed unsuffixed on PATH,
                  in addition to its suffixed copy. Ignored when
                  `versions` is empty. Must be a key of `versions` when
                  non-empty (enforced by lib/validate.nix).
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
