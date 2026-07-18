# &desc: "Direnv generation logic for per-directory shells -- reverses PATH order, generates colorized package lists, handles recursive inheritance."

{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let

  homeDir = config.vars.identity.homeDirectory;
  shells = config.vars.packages.shells;

  # ---------------------------
  # DO NOT MODIFY
  # ---------------------------

  mkEntry =
    index:
    {
      path,
      packages,
      recursive ? true,
    }:
    let
      # Reversed so the first-declared package ends up earliest on PATH --
      # PATH_add always prepends, so building in reverse order restores
      # the declared precedence.
      bins = lib.reverseList (lib.splitString ":" (lib.makeBinPath packages));

      pkgLines =
        colorCode:
        lib.concatMapStringsSep "\n  " (
          p: ''printf "  [ \033[${colorCode}m•\033[0m ] %s (%s)\n" "${lib.getName p}" "${lib.getVersion p}"''
        ) packages;

      body = lib.concatMapStringsSep "\n  " (b: ''PATH_add "${b}"'') bins;

      # recursive = false: block inheritance into whatever subdirectories
      # already exist by giving each one an empty .envrc -- direnv stops
      # at the nearest ancestor, so an empty file there prevents it from
      # walking further up to this one. Only covers subdirectories that
      # exist at rebuild time; a new one added later needs a rebuild to
      # be excluded too.
      blockedChildren =
        if recursive || !(builtins.pathExists path) then
          [ ]
        else
          lib.mapAttrsToList (name: _: path + "/${name}") (
            lib.filterAttrs (_: type: type == "directory") (builtins.readDir path)
          );
    in
    {
      inherit path body blockedChildren;
      id = "shell_${toString index}";
      # green dot + text, aligned with the package bullets below it
      loadingBanner = ''
        printf "  [ \033[32m•\033[0m ] \033[32mLoading environment\033[0m\n"
        ${pkgLines "32"}
      '';
      # same layout, red dot + text, for when this shell's scope is left
      unloadingBanner = ''
        printf "  [ \033[31m•\033[0m ] \033[31mUnloading environment\033[0m\n"
        ${pkgLines "31"}
      '';
    };

  entries = lib.imap0 mkEntry shells;

  toHomeRelative = path: lib.removePrefix "/" (lib.removePrefix homeDir path);

  direnvrc = ''
    _ds_state_file() {
      local tty_slug
      tty_slug="$(tty 2>/dev/null | tr -c 'a-zA-Z0-9' '_')"
      echo "$HOME/.cache/declarative-shells/active''${tty_slug:-_notty}"
    }

    # Prints the unloading banner for whichever shell id is passed, if any.
    _ds_print_unload() {
      case "$1" in
      ${lib.concatMapStringsSep "\n" (e: ''
        ${e.id})
        ${e.unloadingBanner}
          ;;
      '') entries}
      esac
    }

    # $1 = id of the shell about to become active, or "" if none (called
    # from the $HOME anchor). Prints the previous shell's unload banner
    # if it differs, then updates/clears the per-terminal state file.
    _ds_check_transition() {
      local state_file prev
      state_file="$(_ds_state_file)"
      if [[ -f "$state_file" ]]; then
        prev="$(cat "$state_file")"
        if [[ -n "$prev" && "$prev" != "$1" ]]; then
          _ds_print_unload "$prev"
        fi
      fi
      if [[ -z "$1" ]]; then
        rm -f "$state_file"
      fi
    }

    use_declarative_shell_anchor() {
      _ds_check_transition ""
    }

    ${lib.concatMapStringsSep "\n" (e: ''
      use_declarative_${e.id}() {
        local _ds_prev=""
        [[ -f "$(_ds_state_file)" ]] && _ds_prev="$(cat "$(_ds_state_file)")"
        _ds_check_transition "${e.id}"
        if [[ "$_ds_prev" != "${e.id}" ]]; then
      ${e.loadingBanner}
        fi
      ${e.body}
        mkdir -p "$(dirname "$(_ds_state_file)")"
        echo "${e.id}" > "$(_ds_state_file)"
      }
    '') entries}
  '';

  ownEnvrcFiles = lib.listToAttrs (
    map (e: {
      name = "${toHomeRelative e.path}/.envrc";
      value.text = "use declarative_${e.id}\n";
    }) entries
  );

  blockingEnvrcFiles = lib.listToAttrs (
    lib.concatMap (
      e:
      map (child: {
        name = "${toHomeRelative child}/.envrc";
        value.text = "";
      }) e.blockedChildren
    ) entries
  );

  # Shell backup line
  # anchorEnvrcFile = lib.optionalAttrs (entries != [ ]) {
  #   ".envrc".text = "use declarative_shell_anchor\n";
  # };

  anchorEnvrcFile = lib.optionalAttrs (entries != [ ] || config.vars.packages.venvs.venvs != { }) {
    ".envrc".text = ''
      use declarative_shell_anchor
      source_env ~/.config/direnv/venvrc
      use declarative_venv_anchor
    '';
  };

in
{
  # programs.direnv.* now lives in config/packages/programs.nix.

  home-manager.users.${config.vars.identity.username} = {
    home.file =
      ownEnvrcFiles
      // blockingEnvrcFiles
      // anchorEnvrcFile
      // {
        ".config/direnv/direnvrc".text = direnvrc;
      };

    # direnv refuses to run an .envrc it hasn't seen/hashed before, for
    # any content change. Auto-allow every declared path's .envrc (plus
    # the $HOME anchor) on activation so that never needs doing by hand
    # -- their content is a static one-liner each (the real logic lives
    # in direnvrc, which isn't gated), so in practice this only ever
    # needs to fire once per declared path.
    home.activation.allowDeclarativeShells =
      inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ]
        ''
          ${lib.optionalString (entries != [ ]) ''
            $DRY_RUN_CMD ${pkgs.direnv}/bin/direnv allow "$HOME"
          ''}
          ${lib.concatMapStrings (e: ''
            $DRY_RUN_CMD ${pkgs.direnv}/bin/direnv allow "${e.path}"
          '') entries}
        '';
  };
}
