# &desc: "Prism Launcher home-manager config -- package override (Kvantum theming), Dolphin-matching QPalette theme, pinned settings."

{ config, pkgs, ... }:

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

    # Upstream's package only ships qtbase/qtimageformats/qtsvg/qtwayland
    # in buildInputs, so wrapQtAppsHook's QT_PLUGIN_PATH never gets a
    # styles/ dir at all -- Prism can only ever fall back to Qt's built-in
    # Fusion, no matter what theme.json says, without this. Adding
    # kdePackages.qtstyleplugin-kvantum to buildInputs is enough:
    # wrapQtAppsHook's qtHostPathHook env-hook
    # (qt-6/hooks/wrap-qt-apps-hook.sh) fires automatically for every
    # buildInput at build time and appends <pkg>/lib/qt-6/plugins to
    # QT_PLUGIN_PATH on its own -- no manual wrapProgram/makeWrapper
    # needed, this is the same mechanism qtbase itself uses to register
    # its own plugins.
    #
    # Kvantum, not Breeze: Dolphin/Gwenview's actual look (rounded
    # corners, translucent blur, teal accent/glow) is a Kvantum SVG theme
    # (Fluent-Dark, see ../../../../Themes/Kvantum/Fluent-Dark), not a
    # QPalette recolor of a QStyle -- confirmed by ~/.config/qt6ct's
    # style=kvantum-dark and Kvantum's own kvantum.kvconfig
    # [Applications] override for dolphin/gwenview. Breeze (tried first)
    # only ever reproduces Breeze's own shapes with different colors, it
    # was never going to match. "prismlauncher" is added to that same
    # [Applications] line in ../../../../Themes/Kvantum/kvantum.kvconfig
    # so Kvantum's plugin picks Fluent-Dark for it specifically, same as
    # it does for dolphin/gwenview, instead of the system-wide default.
    package = pkgs.prismlauncher.overrideAttrs (old: {
      buildInputs = old.buildInputs ++ [ pkgs.kdePackages.qtstyleplugin-kvantum ];
    });

    # settings is controlled impurity, not a full declarative config: its
    # activation script (impureConfigMerger, upstream prismlauncher.nix)
    # crudini --merge's only the keys listed here into the real, mutable
    # $XDG_DATA_HOME/PrismLauncher/prismlauncher.cfg on every rebuild --
    # it never truncates or symlinks the file. Anything the app itself
    # writes to that file (window geometry, last-used account, etc.) that
    # isn't one of these keys survives untouched across rebuilds. Instances
    # and worlds live entirely under .../PrismLauncher/instances/ and are
    # never touched by this module at all, declared or not -- add/manage
    # those from the app UI same as always. (.../PrismLauncher itself is a
    # symlink to vars.minecraft.prism.location -- see ./portable.nix and
    # modules/services/minecraft-prism -- so this all still ends up under
    # that one portable folder.)
    #
    # ApplicationTheme selects a theme by its folder name under
    # $XDG_DATA_HOME/PrismLauncher/themes/ (Application.cpp:
    # registerSetting("ApplicationTheme", ...)) -- "Dolphin" here is the
    # `themes."Dolphin"` entry below, whose name matches the theme dir.
    settings.ApplicationTheme = "Dolphin";

    # Colors lifted from Kvantum Fluent-Dark's own [GeneralColors]
    # (../../../../Themes/Kvantum/Fluent-Dark/Fluent-Dark.kvconfig) --
    # window #121212, highlight/accent #5294e2, link #4aaff7 -- not
    # qt6ct's style-colors.conf, which is a different, mostly-unused
    # QPalette that Kvantum's SVG rendering ignores for almost everything
    # it draws itself. This QPalette still matters for whatever Kvantum's
    # theme doesn't skin directly, so it's kept close to Fluent-Dark's own
    # values rather than left at Qt defaults. Kept as its own repo dir
    # (Themes/Prism/) rather than inline attrs so it's easy to diff
    # against Fluent-Dark.kvconfig by eye if that theme ever changes.
    themes."Dolphin" = ../../../../../Themes/Prism;
  };
}
