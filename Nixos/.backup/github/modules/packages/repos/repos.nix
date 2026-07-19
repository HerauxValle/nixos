# &desc: "Git repo reconciler companion to venvs/venv.nix -- path resolution, ~ expansion, JSON handoff to lib/sync.sh."

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let

  homeDir = config.vars.identity.homeDirectory;
  cfg = config.vars.packages.repos;

  # ---------------------------------------------------------------------
  # Path resolution -- identical trick to venvs/venv.nix's expandHome.
  # ---------------------------------------------------------------------

  expandHome = p: if lib.hasPrefix "~" p then homeDir + (lib.removePrefix "~" p) else p;

  basePath = expandHome cfg.basePath;

  resolvedRepos = lib.mapAttrs (
    name: r:
    r
    // {
      resolvedPath = if r.path != null then expandHome r.path else "${basePath}/${name}";
    }
  ) cfg.repos;

  # Two different repo names resolving to the same on-disk path would mean
  # whichever runs second silently reconfigures the first one's checkout
  # against a different declaration -- catch that at eval time instead.
  pathCounts = lib.foldl' (
    acc: p: acc // { ${p} = (acc.${p} or 0) + 1; }
  ) { } (map (r: r.resolvedPath) (lib.attrValues resolvedRepos));
  collidingPaths = lib.filterAttrs (_: n: n > 1) pathCounts;

  assertNoPathCollisions =
    lib.assertMsg (collidingPaths == { })
      "vars.packages.repos: multiple repos resolve to the same path: ${lib.concatStringsSep ", " (lib.attrNames collidingPaths)}.";

  # ---------------------------------------------------------------------
  # reposync -- one JSON blob per repo rather than N shell args, so
  # lib/sync-one.sh stays small and doesn't grow a new positional arg
  # every time a schema field is added. Same trick as venvctl's
  # VENVCTL_DATA in venvs/venv.nix.
  # ---------------------------------------------------------------------

  reposJson = builtins.toJSON (
    lib.mapAttrs (_: r: {
      inherit (r)
        url
        initialBranch
        remotes
        userName
        userEmail
        signingKey
        gpgSign
        hooksPath
        excludesFile
        extraConfig
        ;
      path = r.resolvedPath;
    }) resolvedRepos
  );

  # ${./lib} copies the whole subtree as one store path, so sync.sh can
  # find sync-one.sh at a stable runtime root via $REPOCTL_LIBROOT --
  # same reasoning as venvs' $VENVCTL_LIBROOT.
  libRoot = ./lib;

in
{
  assertions = [
    {
      assertion = assertNoPathCollisions;
      message = "repo path collision";
    }
  ];

  home-manager.users.${config.vars.identity.username} = {
    # Runs on every rebuild, not gated behind any other activation entry --
    # unlike venvs there's no direnv-allow step this needs to happen after.
    # $DRY_RUN_CMD means `pacnix validate`/dry-run activations never clone
    # or touch git config, matching venv.nix's own dry-run handling.
    # git/jq resolved to absolute store paths, and GIT_SSH_COMMAND likewise
    # -- activation scripts don't have git (or ssh) on PATH by default,
    # same caveat as modules/backup/dotfiles/lib/default.nix's
    # $dotfilesBackupGit; PATH manipulation is deliberately avoided here.
    home.activation.syncDeclarativeRepos =
      inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ]
        ''
          export REPOCTL_LIBROOT=${libRoot}
          export REPOCTL_DATA=${lib.escapeShellArg reposJson}
          export REPOCTL_GIT=${pkgs.git}/bin/git
          export REPOCTL_JQ=${pkgs.jq}/bin/jq
          export GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh
          $DRY_RUN_CMD ${pkgs.bash}/bin/bash "${libRoot}/sync.sh"
        '';
  };
}
