{ ... }:

# Personal picks -- which of YOUR scripts get exposed as PATH commands.
# Concatenated with modules/packages/scripts/default.nix's own entry
# (pacnix, the one generic default) via Nix's normal listOf-option merge
# behavior, not a custom mechanism. No options.vars declaration needed
# here, same as config/customized.nix -- that lives in modules/ instead.
{
  config.vars.scripts = [

    {
      dir = ../../Scripts/Reload;
      include = {
        "qsr.sh" = "qsr";
      };
    }

    {
      # wallpaper.jpg lives alongside reload.sh here (not in a separate
      # Wallpaper/ folder) specifically so this folder is self-contained
      # -- copying it doesn't drag in anything else from Scripts/.
      dir = ../../Scripts/Wallpaper;
      include = {
        "reload.sh" = "wallpaper";
      };
    }

    {
      # multi-file project: main.sh sources ./modules/*.sh relative to
      # itself. Hyprland keybinds/autostart call it by full path already
      # (sourceMe.lua); this just also puts it on PATH as `hyprfloat` for
      # manual/CLI use (--status, --conflicts, etc).
      dir = ../../Hyprland/Floating;
      include = {
        "main.sh" = "hyprfloat";
      };
    }

    {
      # frecency-scored directory/file launcher + alias manager, used by
      # cd.fish alongside zoxide. Own DB at ~/.local/share/lookup/.
      dir = ../../Scripts/Run;
      include = {
        "run.sh" = "run";
      };
    }

    {
      # Dispatcher for /etc/nixos-secrets/ management (password hash,
      # dotfiles-backup deploy key) -- writes to /etc/nixos-secrets/, not the
      # Nix store, so no $0-relative path concerns like sudo's below; fine
      # to expose here. Multi-file project: secrets.sh sources ./cmd/*.sh
      # relative to itself.
      dir = ../../Scripts/Secrets;
      include = {
        "secrets.sh" = "secrets";
      };
    }

    # sudo isn't listed here: it needs to land at ~/.local/bin (earlier in
    # $PATH than real sudo, at /run/wrappers/bin) to actually intercept
    # "sudo" -- this file's own systemPackages placement never would. See
    # home/apps.nix's "home.file.\".local/bin/sudo\"" instead.

    # {
    #   dir = ../../../Projects/Path;
    #   include = { "bin" = "path"; };
    # }

  ];
}
