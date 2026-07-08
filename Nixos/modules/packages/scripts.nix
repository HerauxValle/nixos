{ pkgs, lib, ... }:

let

  # Each entry: a folder, and exactly which files inside it to expose as
  # commands (filename -> desired command name). This is the one place
  # both simple standalone scripts and multi-file projects (an
  # entrypoint that sources sibling files relative to itself, e.g.
  # Projects/Path's `bin`, which sources ../cmd/*.sh and ../lib/common.sh)
  # get declared — the wrapping mechanism (copy the whole folder,
  # symlink just the named file) is identical either way. Only files
  # listed in `include` become commands; nothing else in the folder is
  # touched. Most of these scripts are keybind/startup-only (no real "type
  # this manually" use case) so they're left out — only genuinely
  # interactive commands are listed. A `dir` that doesn't exist, or a
  # file in `include` that doesn't exist in it, is skipped silently, no
  # error — it just isn't installed until it does.

  scripts = [

    {
      dir = ../../../Scripts/Reload;
      include = {
        "qsr.sh" = "qsr";
      };
    }

    {
      # wallpaper.jpg lives alongside reload.sh here (not in a separate
      # Wallpaper/ folder) specifically so this folder is self-contained
      # — copying it doesn't drag in anything else from Scripts/.
      dir = ../../../Scripts/Wallpaper;
      include = {
        "reload.sh" = "wallpaper";
      };
    }

    {
      # multi-file project: main.sh sources ./cmd/*.sh and ./lib/*.sh
      # relative to itself.
      dir = ../../../Scripts/Pacnix;
      include = {
        "main.sh" = "pacnix";
      };
    }

    {
      # multi-file project: main.sh sources ./modules/*.sh relative to
      # itself. Hyprland keybinds/autostart call it by full path already
      # (sourceMe.lua); this just also puts it on PATH as `hyprfloat` for
      # manual/CLI use (--status, --conflicts, etc).
      dir = ../../../Hyprland/Floating;
      include = {
        "main.sh" = "hyprfloat";
      };
    }

    {
      # frecency-scored directory/file launcher + alias manager, used by
      # cd.fish alongside zoxide. Own DB at ~/.local/share/lookup/.
      dir = ../../../Scripts/Run;
      include = {
        "run.sh" = "run";
      };
    }

    {
      # Dispatcher for /etc/nixos-secrets/ management (password hash,
      # dotfiles-backup deploy key) — writes to /etc/nixos-secrets/, not the
      # Nix store, so no $0-relative path concerns like sudo's below; fine
      # to expose here. Multi-file project: secrets.sh sources ./cmd/*.sh
      # relative to itself.
      dir = ../../../Scripts/Secrets;
      include = {
        "secrets.sh" = "secrets";
      };
    }

    # sudo isn't listed here: it needs to land at ~/.local/bin (earlier in
    # $PATH than real sudo, at /run/wrappers/bin) to actually intercept
    # "sudo" — this file's own systemPackages placement never would. See
    # home/apps.nix's "home.file.\".local/bin/sudo\"" instead.

    # {
    #   dir = ../../../../Projects/Path;
    #   include = { "bin" = "path"; };
    # }

  ];

  # Copies the script's whole containing folder into the store (so any
  # sibling files it sources relative to itself keep resolving) and
  # symlinks just that one file onto PATH as `name`.

  wrapScript = name: path:

    if builtins.pathExists path then

      pkgs.runCommand name { } ''

        mkdir -p $out/opt $out/bin
        cp -r ${dirOf path} $out/opt/src
        chmod +x "$out/opt/src/${baseNameOf path}"
        ln -s "$out/opt/src/${baseNameOf path}" "$out/bin/${name}"

      ''
    else
      null;

  wrapEntry = { dir, include }:
    lib.mapAttrsToList (fname: cmdName: wrapScript cmdName (dir + "/${fname}")) include;

in

{
  environment.systemPackages =
    lib.filter (p: p != null) (lib.concatMap wrapEntry scripts);
}
