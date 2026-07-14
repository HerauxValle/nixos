{ config, lib, pkgs, inputs, ... }:

# Companion to ../shells/shells.nix. Read docs/ARCHITECTURE.md first if
# this is your first time in this file -- it explains why venvs can't
# reuse shells' direnvrc-sharing trick (mutable pip state vs. pure
# symlinked .envrc content), and why the manifest path below is hardcoded
# instead of computed from a nix path literal.

let

  homeDir = config.vars.homeDirectory;
  cfg = config.vars.venvs;

  # ---------------------------------------------------------------------
  # Path resolution
  # ---------------------------------------------------------------------

  expandHome = p: if lib.hasPrefix "~" p
    then homeDir + (lib.removePrefix "~" p)
    else p;

  basePath = expandHome cfg.basePath;

  resolvedVenvs = lib.mapAttrs (name: v: v // {
    resolvedPath =
      if v.path != null then expandHome v.path else "${basePath}/${name}";
    # Resolved at eval time, not left for build.sh to find on PATH --
    # otherwise "python = \"python311\";" is display-only and every venv
    # silently gets whatever bare `python3` happens to resolve to at
    # activation time (which may be nothing at all -- see build.sh).
    # lib.hasAttr check below gives a venv-specific error message instead
    # of nix's generic "attribute missing" if you typo the attr name.
    pythonBin =
      if lib.hasAttr v.python pkgs then "${pkgs.${v.python}}/bin/python3"
      else throw ''
        vars.venvs.venvs.${name}.python = "${v.python}" is not a valid
        nixpkgs attribute (checked pkgs.${v.python}). Common values:
        python3, python310, python311, python312, python313.'';
  }) cfg.venvs;

  # Effective activation trigger dirs per venv: explicit paths win outright
  # (no merge with the implicit default -- see default.nix option doc).
  effectiveActivation = lib.mapAttrs (name: v:
    if v.activation.onEntry && v.activation.paths == { } then
      { "${v.resolvedPath}" = "recursive"; }
    else if v.activation.onEntry then
      lib.mapAttrs' (p: mode: lib.nameValuePair (expandHome p) mode) v.activation.paths
    else { }
  ) resolvedVenvs;

  # ---------------------------------------------------------------------
  # Assert-and-forbid: a dir can be a declared shell XOR a declared venv
  # trigger, never both. See docs/DECISIONS.md "Assert vs. Merge".
  # ---------------------------------------------------------------------

  shellPaths = map (s: expandHome s.path) config.vars.shells;
  venvTriggerPaths = lib.unique (lib.concatMap (a: lib.attrNames a) (lib.attrValues effectiveActivation));
  collisions = lib.intersectLists shellPaths venvTriggerPaths;

  assertNoCollisions =
    lib.assertMsg (collisions == [ ])
      "vars.shells and vars.venvs.venvs.*.activation.paths collide on: ${lib.concatStringsSep ", " collisions}. A directory may be a declared shell or a declared venv trigger, not both.";

  # ---------------------------------------------------------------------
  # Manifest path. NOT a relative nix path literal on purpose: ./. inside
  # a flake-evaluated module resolves to an immutable /nix/store copy, so
  # toString ./. would point at a read-only store path instead of your
  # live checkout -- see docs/DECISIONS.md "Why the manifest path is
  # hardcoded". This is the one deliberate exception to "always relative".
  # ---------------------------------------------------------------------

  manifestPath = "${homeDir}/Dotfiles/.store/venvs.json";
  lockRoot = "${homeDir}/Dotfiles/Python/locks/nix-managed";

  # ---------------------------------------------------------------------
  # direnv wiring. Separate file from shells' direnvrc so the two modules
  # never both own home.file.".config/direnv/direnvrc" -- see
  # docs/DECISIONS.md "source_env instead of a shared direnvrc".
  # ---------------------------------------------------------------------

  mkUseFunction = name: v: ''
    use_venv_${name}() {
      printf "  [ \033[32m•\033[0m ] \033[32mActivating venv\033[0m %s (python: ${v.python})\n" "${name}"
      export VIRTUAL_ENV="${v.resolvedPath}"
      PATH_add "${v.resolvedPath}/bin"
    }
  '';

  venvrc = lib.concatStringsSep "\n" (lib.mapAttrsToList mkUseFunction resolvedVenvs);

  ownEnvrcFiles = lib.foldl' (acc: name:
    let paths = lib.attrNames effectiveActivation.${name}; in
    acc // lib.listToAttrs (map (p: {
      name = "${lib.removePrefix "/" (lib.removePrefix homeDir p)}/.envrc";
      value.text = ''
        source_env ~/.config/direnv/venvrc
        use venv_${name}
      '';
    }) paths)
  ) { } (lib.attrNames effectiveActivation);

  # Same blocking trick as shells.nix: an empty .envrc in an existing
  # child dir stops direnv walking up into a "flat" trigger's parent.
  blockedChildrenFor = path: mode:
    if mode == "recursive" || !(builtins.pathExists path) then [ ]
    else lib.mapAttrsToList (n: _: path + "/${n}")
      (lib.filterAttrs (_: t: t == "directory") (builtins.readDir path));

  blockingEnvrcFiles = lib.foldl' (acc: name:
    let paths = effectiveActivation.${name}; in
    acc // lib.listToAttrs (lib.concatLists (lib.mapAttrsToList (p: mode:
      map (child: {
        name = "${lib.removePrefix "/" (lib.removePrefix homeDir child)}/.envrc";
        value.text = "";
      }) (blockedChildrenFor p mode)
    ) paths))
  ) { } (lib.attrNames effectiveActivation);

  # ---------------------------------------------------------------------
  # venvctl -- single entrypoint binary, dispatches into lib/cli/*.sh.
  # Each venv's resolved data is baked in as one JSON blob rather than
  # passed as N shell args, so lib/cli scripts stay small and don't grow
  # a new flag every time an option field is added.
  # ---------------------------------------------------------------------

  venvsJson = builtins.toJSON (lib.mapAttrs (_: v: {
    inherit (v) resolvedPath python pythonBin packages lockfile;
    activation = effectiveActivation.${_} or { };
  }) resolvedVenvs);

  # ${./lib} copies the whole subtree as one store path (not per-file),
  # so every script under it can find its siblings at a stable runtime
  # root via $VENVCTL_LIBROOT instead of each getting its own disjoint
  # store path. This is why lib/ scripts source each other with
  # "$VENVCTL_LIBROOT/manage/whatever.sh" rather than relative ../.
  libRoot = ./lib;

  venvctl = pkgs.writeShellApplication {
    name = "venvctl";
    runtimeInputs = [ pkgs.jq pkgs.python3 ];
    text = ''
      export VENVCTL_LIBROOT=${libRoot}
      export VENVCTL_DATA=${lib.escapeShellArg venvsJson}
      export VENVCTL_MANIFEST=${lib.escapeShellArg manifestPath}
      export VENVCTL_LOCKROOT=${lib.escapeShellArg lockRoot}
      export VENVCTL_LOGLEVEL=${lib.escapeShellArg cfg.logLevel}
      exec "${libRoot}/cli/cli.sh" "$@"
    '';
  };

in
{
  assertions = [{ assertion = assertNoCollisions; message = "venv/shell path collision"; }];

  home-manager.users.${config.vars.username} = {
    home.packages = [ venvctl ];

    home.file = ownEnvrcFiles // blockingEnvrcFiles // lib.optionalAttrs (resolvedVenvs != { }) {
      ".config/direnv/venvrc".text = venvrc;
    };
    # Fish shim is NOT installed here -- this module doesn't own
    # ~/.config/fish (see docs/DECISIONS.md "Shim distribution"). Copy
    # lib/shims/activate.fish into wherever your own fish config source
    # lives (e.g. Dotfiles/Shells/Fish/conf.d/) so your existing
    # xdg.configFile symlink picks it up.

    home.activation.allowDeclarativeVenvs = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${lib.optionalString (ownEnvrcFiles != { }) ''
        $DRY_RUN_CMD ${pkgs.direnv}/bin/direnv allow "$HOME"
        ${lib.concatMapStrings (name: lib.concatMapStrings (p: ''
          $DRY_RUN_CMD ${pkgs.direnv}/bin/direnv allow "${p}"
        '') (lib.attrNames effectiveActivation.${name})) (lib.attrNames effectiveActivation)}
      ''}
    '';

    # Build/prune runs after allow, so a fresh .envrc is already trusted
    # by the time build.sh potentially triggers anything direnv-adjacent.
    home.activation.buildDeclarativeVenvs = inputs.home-manager.lib.hm.dag.entryAfter [ "allowDeclarativeVenvs" ] ''
      export VENVCTL_LIBROOT=${libRoot}
      export VENVCTL_DATA=${lib.escapeShellArg venvsJson}
      export VENVCTL_MANIFEST=${lib.escapeShellArg manifestPath}
      export VENVCTL_LOCKROOT=${lib.escapeShellArg lockRoot}
      export VENVCTL_LOGLEVEL=${lib.escapeShellArg cfg.logLevel}
      $DRY_RUN_CMD ${pkgs.bash}/bin/bash "${libRoot}/manage/sync.sh"
    '';
  };
}
