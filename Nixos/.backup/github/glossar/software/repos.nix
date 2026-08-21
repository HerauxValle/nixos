# &desc: "Commented example reference for config.vars.packages.repos -- declarative git repo registry with clone/remote/local-config reconciliation, companion to repos.nix."

{ ... }:

# ==========================================================================
# EXAMPLES -- every config.vars.packages.repos option, all commented out.
# Same shape as glossar/software/venvs.nix, scoped to one module. Schema:
# modules/packages/repos/default.nix. Logic that turns this into real
# clones + enforced git config: modules/packages/repos/repos.nix + lib/.
#
# `url` is the only required field per repo -- everything else (path,
# remotes, local git config) either has a sensible default or is left
# untouched (null) if omitted.
#
# `path`, when omitted, resolves to `${basePath}/<name>` -- same
# resolution-happens-elsewhere caveat as venvs' basePath: this file is
# never imported, so there's no live config to reference here, only the
# shape to copy.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/software/environment/repos.nix and uncomment it there to
# actually declare it.
# ==========================================================================

{
  # config.vars.packages.repos = {

  #   # --- globals -----------------------------------------------------
  #   basePath = "~/Projects"; # default parent for repos w/o their own `path`

  #   repos = {

  #     # --- every field, one repo ----------------------------------------
  #     some-project = {
  #       url = "git@github.com:someuser/some-project.git"; # origin -- enforced every rebuild, also used for the initial clone
  #       path = null;          # null = derive as basePath/<name>; or set an override e.g. "~/dev/some-project"
  #       initialBranch = null; # branch checked out the first time this repo gets content; null = remote's own default branch. Never force-switches an already-existing checkout.
  #       remotes = {
  #         upstream = "git@github.com:upstream-owner/some-project.git"; # extra remotes beyond origin, name -> url, enforced every rebuild
  #       };
  #       userName = null;    # git config --local user.name override; null = don't touch it
  #       userEmail = null;   # git config --local user.email override; null = don't touch it
  #       signingKey = null;  # git config --local user.signingKey override (GPG key ID or SSH key path); null = don't touch it
  #       gpgSign = null;     # git config --local commit.gpgSign override; null = don't touch it
  #       hooksPath = null;   # git config --local core.hooksPath override -- point at a Nix-managed hooks dir; null = don't touch it
  #       excludesFile = null; # git config --local core.excludesFile override; null = don't touch it
  #       extraConfig = {
  #         "pull.rebase" = "true"; # escape hatch for any other `git config --local <key> <value>` not covered above
  #       };
  #     };

  #     # --- minimal repo -- clone/keep-in-sync, no local config touched --
  #     scratch = {
  #       url = "git@github.com:someuser/scratch.git";
  #     };

  #   };

  # };

  # --- existence + local git config are Nix-owned and reconciled every
  # rebuild (clone if missing, remotes/config enforced). Commit history,
  # working tree contents, and whichever branch is currently checked out
  # are never touched -- that's your actual work, not config. See
  # modules/packages/repos/lib/sync-one.sh for the exact safety model
  # (no --force/--hard anywhere; a real conflict surfaces as a reported
  # failure, never silently overridden).
}
