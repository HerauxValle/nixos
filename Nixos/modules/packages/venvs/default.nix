{ lib, ... }:

# Schema only -- mirrors the convention in ../shells/default.nix.
# No default venvs are declared here (same reasoning as shells: what you
# want built is personal config, not schema). Actual generation logic
# (manifest diffing, home.activation entries, direnv wiring) lives in
# ./venv.nix, imported below. Everything else in ./lib is either sourced
# by venv.nix at build time or shipped as standalone executables --
# neither is imported here, per the "default.nix only imports what's in
# its own dir" rule (lib/ is still "in its own dir", but its .sh files
# aren't nix modules, so there's nothing to import -- venv.nix reaches
# into lib/ directly via ./lib/... paths when it needs them).
{
  imports = [ ./venv.nix ];

  options.vars.packages.venvs = lib.mkOption {
    type = lib.types.submodule {
      options = {
        logLevel = lib.mkOption {
          type = lib.types.enum [ "debug" "silent" "error" ];
          default = "error";
          description = ''
            Verbosity for build/install/update output during rebuild and
            manual venvctl invocations. debug = everything, error = only
            failures, silent = nothing but a final success/error line.
          '';
        };

        basePath = lib.mkOption {
          type = lib.types.str;
          default = "~/.impure/python-venvs/nix-declared";
          description = ''
            Default parent dir for venvs that don't set their own `path`.
            `~` is expanded against config.vars.identity.homeDirectory, not the
            shell's HOME, since this gets baked into nix-generated files
            at eval time -- see docs/DECISIONS.md.
          '';
        };

        venvs = lib.mkOption {
          default = { };
          description = "Declared venvs, keyed by name.";
          type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
            options = {
              path = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Override install path; defaults to basePath/<name> if unset.";
              };

              python = lib.mkOption {
                type = lib.types.str;
                default = "python3";
                description = "Nixpkgs attribute name for the interpreter, e.g. \"python311\".";
              };

              packages = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
                description = ''
                  PyPI name -> version. Use "latest" to float -- floating
                  packages are NOT touched on rebuild, only by an explicit
                  `venvctl update <name|all>` run. See docs/DECISIONS.md
                  for why rebuild deliberately never auto-bumps these.
                '';
              };

              activation = lib.mkOption {
                default = { };
                description = "direnv on-entry activation for this venv.";
                type = lib.types.submodule {
                  options = {
                    onEntry = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Whether entering a trigger dir activates this venv via direnv.";
                    };

                    paths = lib.mkOption {
                      type = lib.types.attrsOf (lib.types.enum [ "recursive" "flat" ]);
                      default = { };
                      description = ''
                        Explicit trigger dirs -> recursive/flat, same semantics
                        as config.vars.packages.shells. If empty and onEntry = true, the
                        venv's own resolved path is used as a single recursive
                        trigger. Declaring even one explicit path here fully
                        replaces that implicit default -- it does not append.
                      '';
                    };
                  };
                };
              };

              lockfile = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  If true, build/update writes resolved versions to
                  Dotfiles/Python/locks/nix-managed/<name>/*.lock (staged
                  as *.lock.new before promotion). Off by default; nothing
                  lock-related runs otherwise.
                '';
              };
            };
          }));
        };
      };
    };
    default = { };
    description = "Declarative Python venvs -- see venvs/docs/README.md.";
  };
}
