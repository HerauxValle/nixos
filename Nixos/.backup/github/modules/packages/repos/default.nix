# &desc: "Declarative git push-target registry schema (no defaults) -- existing local dirs -> named remotes, squash/history push. Logic lives in ./repos.nix + ./lib, driven by the reposctl CLI (pacnix github push/release)."

{ lib, ... }:

# Schema only -- mirrors the convention in ../venvs/default.nix. Nothing
# declared here is ever cloned or created: `path` must already exist on
# disk, this is purely a registry of where your existing local projects
# live and which remotes/modes to push them to. See
# Nixos/config/software/environment/repos.nix for the actual list, and
# glossar/software/repos.nix for a fully commented example of every
# field. Replaces ~/Scripts/Python/gitpushall.py's hardcoded
# REMOTES/SUBTREES/GITHUB_REPOS dicts with the same shape, declared here
# instead.
{
  imports = [ ./repos.nix ];

  options.vars.packages.repos = lib.mkOption {
    type = lib.types.submodule {
      options = {
        repos = lib.mkOption {
          default = { };
          description = "Declared push targets, keyed by name. See modules/packages/repos/lib for push logic.";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                path = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    Existing local directory -- never cloned, never
                    created. `pacnix github push`/`release` fails loudly
                    if this doesn't exist rather than silently skipping
                    it. `~` is expanded against
                    config.vars.identity.homeDirectory at eval time.
                  '';
                };

                remotes = lib.mkOption {
                  description = "Push destinations for this repo, keyed by remote name.";
                  type = lib.types.attrsOf (
                    lib.types.submodule {
                      options = {
                        url = lib.mkOption {
                          type = lib.types.str;
                          description = "Remote URL to push to.";
                        };

                        mode = lib.mkOption {
                          type = lib.types.enum [
                            "squash"
                            "history"
                          ];
                          description = ''
                            "squash": copy `path`'s current working-tree
                            contents (minus excludePaths) into an
                            isolated tmp repo, one commit, force-push --
                            main repo's own .git/history is never
                            touched or required. "history": push `path`'s
                            REAL commit history -- requires path to
                            already be a real git repo; stages+commits
                            any dirty working tree there, rebases onto
                            the remote, then pushes normally (no force).
                          '';
                        };
                      };
                    }
                  );
                };

                excludePaths = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Paths (relative to `path`) stripped from the snapshot before committing -- squash-mode remotes only.";
                };

                excludeFiles = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Paths (relative to `path`) marked `git update-index --assume-unchanged` before staging -- history-mode remotes only.";
                };

                githubRepo = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = ''
                    "owner/repo" slug -- only needed to use `pacnix
                    github release` (creates/deletes a GitHub Release
                    via the API using the token from `secrets github
                    add token`). null = release automation unavailable
                    for this repo, tag+push still works without it.
                  '';
                };
              };
            }
          );
        };
      };
    };
    default = { };
    description = ''
      Declarative git push-target registry: which existing local dirs
      push to which remotes, and how (squash snapshot vs real history).
      Never clones, never touches commit history/working tree of `path`
      itself in squash mode. Pushing only happens when you run `pacnix
      github push`/`release` -- nothing here runs on a plain rebuild.
    '';
  };
}
