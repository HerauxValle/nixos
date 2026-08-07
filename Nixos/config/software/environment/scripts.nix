# &desc: "Scripts exposed as PATH commands -- qsr (reload), wallpaper, hyprfloat (window manager), run (launcher), secrets (vault dispatcher), mac (temporary MAC spoofing)."

{ ... }:

# Personal picks -- which of YOUR scripts get exposed as PATH commands.
# Concatenated with modules/packages/scripts/default.nix's own entry
# (pacnix, the one generic default) via Nix's normal listOf-option merge
# behavior, not a custom mechanism. No options.vars declaration needed
# here, same as config/config.nix -- that lives in modules/ instead.
{
  config.vars.packages.scripts = [

    {
      dir = ../../../../Scripts/Reload;
      include = {
        "qsr.sh" = "qsr";
      };
    }

    {
      # wallpaper.jpg lives alongside reload.sh here (not in a separate
      # Wallpaper/ folder) specifically so this folder is self-contained
      # -- copying it doesn't drag in anything else from Scripts/.
      dir = ../../../../Scripts/Wallpaper;
      include = {
        "reload.sh" = "wallpaper";
      };
    }

    {
      # multi-file project: main.sh sources ./modules/*.sh relative to
      # itself. Hyprland keybinds/autostart call it by full path already
      # (sourceMe.lua); this just also puts it on PATH as `hyprfloat` for
      # manual/CLI use (--status, --conflicts, etc).
      dir = ../../../../Hyprland/Floating;
      include = {
        "main.sh" = "hyprfloat";
      };
    }

    {
      # frecency-scored directory/file launcher + alias manager, used by
      # cd.fish alongside zoxide. Own DB at ~/.local/share/lookup/.
      dir = ../../../../Scripts/Run;
      include = {
        "run.sh" = "run";
      };
    }

    {
      # Dispatcher for /etc/nixos-secrets/ management (password hash,
      # dotfiles-backup deploy key) -- writes to /etc/nixos-secrets/, not the
      # Nix store, so no $0-relative path concerns; fine to expose here.
      # Multi-file project: secrets.sh sources ./cmd/*.sh relative to itself.
      dir = ../../../../Scripts/Secrets;
      include = {
        "secrets.sh" = "secrets";
      };
    }

    {
      # Temporary MAC spoofing (ip link, not nmcli) -- presets live at the
      # top of mac.sh. `default` restores the interface's permanent address.
      dir = ../../../../Scripts/Mac;
      include = {
        "mac.sh" = "mac";
      };
    }

    # {
    #   dir = ../../../../Projects/Path;
    #   include = { "bin" = "path"; };
    # }

  ];
}
