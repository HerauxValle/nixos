# &desc: "Declarative git repos schema (no defaults) -- basePath + repos registry; clone/reconcile logic in ./repos.nix."

{ lib, ... }:

# Schema only -- mirrors the convention in ../venvs/default.nix. No
# default repos are declared here (what you want checked out is personal
# config, not schema). See Nixos/config/software/environment/repos.nix
# for the actual list. Reconciliation logic (clone-if-missing, remote/
# config enforcement) lives in ./repos.nix + ./lib, imported below.
{
  imports = [ ./repos.nix ];

  options.vars.packages.repos = lib.mkOption {
    type = lib.types.submodule {
      options = {
        basePath = lib.mkOption {
          type = lib.types.str;
          default = "~/Projects";
          description = ''
            Default parent dir for repos that don't set their own `path`.
            `~` is expanded against config.vars.identity.homeDirectory, not
            the shell's HOME, since this gets baked into nix-generated
            files at eval time -- same reasoning as venvs' basePath.
          '';
        };

        repos = lib.mkOption {
          default = { };
          description = "Declared git repos, keyed by name. See modules/packages/repos/lib for the reconciliation logic.";
          type = lib.types.attrsOf (
            lib.types.submodule (
              { name, ... }:
              {
                options = {
                  url = lib.mkOption {
                    type = lib.types.str;
                    description = "origin remote URL -- enforced every rebuild (git remote set-url), and used for the initial clone.";
                  };

                  path = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Override checkout path; defaults to basePath/<name> if unset.";
                  };

                  initialBranch = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = ''
                      Branch checked out the first time this repo gets content
                      (a fresh clone, or filling an empty/non-git directory).
                      Never force-switches an already-existing checkout --
                      that's active work, not config, so it's left alone on
                      every rebuild after the first. null = whatever the
                      remote's own default branch is.
                    '';
                  };

                  remotes = lib.mkOption {
                    type = lib.types.attrsOf lib.types.str;
                    default = { };
                    description = "Extra remotes beyond origin, name -> url. Enforced every rebuild like origin.";
                  };

                  userName = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Local (git config --local) user.name override, enforced every rebuild. null = don't touch it.";
                  };

                  userEmail = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Local (git config --local) user.email override, enforced every rebuild. null = don't touch it.";
                  };

                  signingKey = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Local user.signingKey override (GPG key ID or SSH key path), enforced every rebuild. null = don't touch it.";
                  };

                  gpgSign = lib.mkOption {
                    type = lib.types.nullOr lib.types.bool;
                    default = null;
                    description = "Local commit.gpgSign override, enforced every rebuild. null = don't touch it.";
                  };

                  hooksPath = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Local core.hooksPath override -- point at a Nix-managed hooks directory to make hooks declarative too. null = don't touch it.";
                  };

                  excludesFile = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Local core.excludesFile override -- machine-local ignore rules, separate from the tracked .gitignore. null = don't touch it.";
                  };

                  extraConfig = lib.mkOption {
                    type = lib.types.attrsOf lib.types.str;
                    default = { };
                    description = ''
                      Escape hatch for any other `git config --local <key> <value>`
                      not covered by a named option above, e.g. "pull.rebase" = "true".
                      Enforced every rebuild like the named options.
                    '';
                  };
                };
              }
            )
          );
        };
      };
    };
    default = { };
    description = ''
      Declarative git repos: existence + local config are Nix-owned and
      reconciled every rebuild (clone if missing, remotes/git-config
      enforced). Commit history, working tree contents, and whichever
      branch is currently checked out are never touched -- that's your
      actual work, not config.
    '';
  };
}
