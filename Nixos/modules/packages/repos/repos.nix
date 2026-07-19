# &desc: "Git push-target registry companion to venvs/venv.nix -- builds GITCTL_DATA json, packages the gitctl CLI (push/release), deploys the required GitHub classic token."

{
  config,
  lib,
  pkgs,
  ...
}:

let

  homeDir = config.vars.identity.homeDirectory;
  username = config.vars.identity.username;
  cfg = config.vars.packages.repos;

  # ---------------------------------------------------------------------
  # Path resolution -- identical trick to venvs/venv.nix's expandHome.
  # ---------------------------------------------------------------------

  expandHome = p: if lib.hasPrefix "~" p then homeDir + (lib.removePrefix "~" p) else p;

  # ---------------------------------------------------------------------
  # reposJson -- one JSON blob for the whole registry, same trick as
  # venvctl's VENVCTL_DATA: keeps ./lib/*.sh from growing a new
  # positional arg every time a schema field is added.
  # ---------------------------------------------------------------------

  reposJson = builtins.toJSON {
    repos = lib.mapAttrs (_: r: {
      path = expandHome r.path;
      remotes = lib.mapAttrs (_: rem: { inherit (rem) url mode; }) r.remotes;
      inherit (r) excludePaths excludeFiles githubRepo;
    }) cfg.repos;
  };

  # A repo declared with zero remotes would mean `push`/`release` have
  # nothing to actually do for it -- catch that at eval time instead of
  # a confusing no-op at runtime.
  assertions = lib.mapAttrsToList (name: r: {
    assertion = r.remotes != { };
    message = "vars.packages.repos.repos.${name}: declared with zero remotes.";
  }) cfg.repos;

  # ${./lib} copies the whole subtree as one store path, so cli.sh can
  # find push.sh/release.sh/etc at a stable runtime root via
  # $GITCTL_LIBROOT -- same reasoning as venvs' $VENVCTL_LIBROOT.
  libRoot = ./lib;

  # Root-owned source (`secrets github add classic`) -> user-readable
  # copy -- see deployGithubClassicToken below for why this needs its
  # own activation step rather than being read straight from
  # /etc/nixos-secrets. `gitctl release` requires this to exist
  # and errors immediately if it doesn't -- it's not optional the way
  # gitpushall.py's GITHUB_TOKEN env var was.
  tokenFile = "${homeDir}/.config/gitctl/classic-token";

  gitctl = pkgs.writeShellApplication {
    name = "gitctl";
    runtimeInputs = [
      pkgs.git
      pkgs.jq
      pkgs.curl
      pkgs.openssh
    ];
    text = ''
      export GITCTL_LIBROOT=${libRoot}
      export GITCTL_DATA=${lib.escapeShellArg reposJson}
      export GITCTL_TOKEN_FILE=${lib.escapeShellArg tokenFile}
      export GITCTL_COMMIT_NAME=${lib.escapeShellArg cfg.commitUserName}
      export GITCTL_COMMIT_EMAIL=${lib.escapeShellArg cfg.commitUserEmail}
      exec "${libRoot}/cli.sh" "$@"
    '';
  };

in
{
  inherit assertions;

  # Root-owned secret (written by `secrets github add classic`) -> a
  # copy readable by the regular user -- gitctl runs as you, not root,
  # so it can't read /etc/nixos-secrets directly (600 root:root). Same
  # copy-if-source-exists/remove-if-not pattern as
  # modules/security/github-keys.nix's deployKeyScript: presence is a
  # runtime fact this can't see at eval time, so it just reconciles
  # every rebuild.
  system.activationScripts.deployGithubClassicToken.text =
    let
      src = "${config.vars.identity.secretsBaseDir}/github/classic";
    in
    ''
      if [ -f "${src}" ]; then
        install -d -m 700 -o ${username} -g users "${homeDir}/.config/gitctl"
        install -m 600 -o ${username} -g users "${src}" "${tokenFile}"
      else
        rm -f "${tokenFile}"
      fi
    '';

  home-manager.users.${username}.home.packages = [ gitctl ];
}
