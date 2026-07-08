{ config, lib, pkgs, inputs, ... }:

let

  homeDir = "/home/herauxvalle";

  # Each entry: a path, the packages that should be on $PATH while inside
  # it, and whether that also applies to subdirectories (default true --
  # e.g. Dotfiles/Hyprland inherits Dotfiles' shell unless recursive is
  # set false here). Nothing is installed system-wide; packages only
  # exist on $PATH while cwd matches.
  #
  # Implementation note: an earlier version tried to cover every declared
  # path from one shared .envrc anchored at $HOME, matched against $PWD/
  # $OLDPWD from inside the script. That's provably unreliable: direnv
  # only sets an accurate $OLDPWD when it actually has to chdir from the
  # real cwd to the .envrc's directory -- and when the real cwd already
  # *is* $HOME (i.e. exactly the "leave the shell" case), no chdir
  # happens, so $OLDPWD goes stale and PATH never reverts. Verified by
  # hand: cd'ing Dotfiles -> Hyprland -> $HOME left tmux on PATH forever.
  #
  # Fix: give each declared path its own real, Nix-generated .envrc file
  # living right there. direnv's own ancestor-directory search (its
  # actual, battle-tested mechanism) then does all the load/unload work --
  # $PWD inside a loaded .envrc is guaranteed to equal that file's own
  # directory, so no path-matching games are needed for the recursive
  # case at all. Trade-off: a real .envrc is now visible inside the
  # declared directory (e.g. ~/Dotfiles/.envrc) instead of nothing.
  #
  # A $HOME-anchored .envrc also exists purely to print "Unloading" when
  # you leave a shell for somewhere with no shell of its own -- direnv
  # only ever runs script code when it finds an .envrc for the *current*
  # directory, so there's no hook that fires on leaving a directory that
  # has nothing. $HOME is an ancestor of everything under it, so it
  # becomes the nearest .envrc exactly when no shell applies. What shell
  # was previously active can't be read back from an exported env var --
  # verified by hand that direnv reverts those before the next .envrc
  # runs -- so it's tracked in a small state file instead, one per
  # terminal (keyed by tty) so two terminals in different shells don't
  # cross-talk.

  shells = [

    {
      path = "${homeDir}/Dotfiles";
      packages = with pkgs; [ tmux ];
      # recursive = true; # default
    }

  ];

  mkEntry = index: { path, packages, recursive ? true }:
    let
      # Reversed so the first-declared package ends up earliest on PATH --
      # PATH_add always prepends, so building in reverse order restores
      # the declared precedence.
      bins = lib.reverseList (lib.splitString ":" (lib.makeBinPath packages));

      pkgLines = colorCode:
        lib.concatMapStringsSep "\n  " (p: ''
          printf "  [ \033[${colorCode}m•\033[0m ] %s (%s)\n" "${lib.getName p}" "${lib.getVersion p}"'')
          packages;

      body = lib.concatMapStringsSep "\n  " (b: ''PATH_add "${b}"'') bins;

      # recursive = false: block inheritance into whatever subdirectories
      # already exist by giving each one an empty .envrc -- direnv stops
      # at the nearest ancestor, so an empty file there prevents it from
      # walking further up to this one. Only covers subdirectories that
      # exist at rebuild time; a new one added later needs a rebuild to
      # be excluded too.
      blockedChildren =
        if recursive || !(builtins.pathExists path) then [ ]
        else
          lib.mapAttrsToList (name: _: path + "/${name}")
            (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
    in {
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

  toHomeRelative = path:
    lib.removePrefix "/" (lib.removePrefix homeDir path);

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
        _ds_check_transition "${e.id}"
      ${e.loadingBanner}
      ${e.body}
        mkdir -p "$(dirname "$(_ds_state_file)")"
        echo "${e.id}" > "$(_ds_state_file)"
      }
    '') entries}
  '';

  ownEnvrcFiles = lib.listToAttrs (map (e: {
    name = "${toHomeRelative e.path}/.envrc";
    value.text = "use declarative_${e.id}\n";
  }) entries);

  blockingEnvrcFiles = lib.listToAttrs (lib.concatMap
    (e: map (child: {
      name = "${toHomeRelative child}/.envrc";
      value.text = "";
    }) e.blockedChildren)
    entries);

  anchorEnvrcFile = lib.optionalAttrs (entries != [ ]) {
    ".envrc".text = "use declarative_shell_anchor\n";
  };

in
{
  programs.direnv.enable = false;
  # Suppresses the "direnv: loading/using/export" status lines. This is
  # read by the direnv binary itself from /etc/direnv/direnv.toml, not
  # injected into any shell's rc -- applies the same in fish/bash/nu/pwsh
  # without touching any of them.
  programs.direnv.silent = true;

  home-manager.users.herauxvalle = {
    home.file = ownEnvrcFiles // blockingEnvrcFiles // anchorEnvrcFile // {
      ".config/direnv/direnvrc".text = direnvrc;
    };

    # direnv refuses to run an .envrc it hasn't seen/hashed before, for
    # any content change. Auto-allow every declared path's .envrc (plus
    # the $HOME anchor) on activation so that never needs doing by hand
    # -- their content is a static one-liner each (the real logic lives
    # in direnvrc, which isn't gated), so in practice this only ever
    # needs to fire once per declared path.
    home.activation.allowDeclarativeShells = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${lib.optionalString (entries != [ ]) ''
        $DRY_RUN_CMD ${pkgs.direnv}/bin/direnv allow "$HOME"
      ''}
      ${lib.concatMapStrings (e: ''
        $DRY_RUN_CMD ${pkgs.direnv}/bin/direnv allow "${e.path}"
      '') entries}
    '';
  };
}
