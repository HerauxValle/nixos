# &desc: "Prism Launcher program config -- Minecraft mod/modpack/instance launcher with real Modrinth integration, home-manager only."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory -- same reasoning as ./vscode's own
  # enable.nix). Picked over nixpkgs' modrinth-app: that one's wrap step
  # (wrapGAppsHook) is currently broken upstream
  # (wrapGAppsHookHasRunForOutput: bad array subscript, confirmed live),
  # and the unwrapped fallback crashed instantly on Hyprland (Wayland Error
  # 71, a known webkitgtk/wlroots DMA-BUF issue with that Tauri app
  # specifically) before even getting to the missing-icon-theming problem
  # skipping the wrapper causes on top. Prism Launcher is a native Qt app --
  # neither failure mode applies -- and has a real, actively maintained
  # home-manager module, unlike modrinth-app (plain package only, no
  # module).
  config.home-manager.users.${config.vars.identity.username}.programs.prismlauncher = {
    enable = false;

    # settings is controlled impurity, not a full declarative config: its
    # activation script (impureConfigMerger, upstream prismlauncher.nix)
    # crudini --merge's only the keys listed here into the real, mutable
    # $XDG_DATA_HOME/PrismLauncher/prismlauncher.cfg on every rebuild --
    # it never truncates or symlinks the file. Anything the app itself
    # writes to that file (window geometry, last-used account, etc.) that
    # isn't one of these keys survives untouched across rebuilds. Instances
    # and worlds live entirely under .../PrismLauncher/instances/ and are
    # never touched by this module at all, declared or not -- add/manage
    # those from the app UI same as always.
    #
    # ApplicationTheme selects a theme by its folder name under
    # $XDG_DATA_HOME/PrismLauncher/themes/ (Application.cpp:
    # registerSetting("ApplicationTheme", ...)) -- "Dolphin" here is the
    # `themes."Dolphin"` entry below, whose name matches the theme dir.
    settings.ApplicationTheme = "Dolphin";

    # Colors lifted directly from Dolphin's actual live palette --
    # ../../../../Themes/QT/qt6ct/style-colors.conf (Base #2c2c2c, Text
    # #dfdfdf, Accent #12608a) -- not from Gwenview's BreezeDarkTransparent,
    # which is a different KColorScheme file that only happens to look
    # similar. Kept as its own repo dir (Themes/Prism/) rather than inline
    # attrs so it's easy to diff against qt6ct's file by eye if that palette
    # ever changes.
    themes."Dolphin" = ../../../../Themes/Prism;
  };
}
