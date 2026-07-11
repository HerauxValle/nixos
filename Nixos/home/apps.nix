{ config, pkgs, ... }:

{
  xdg.configFile = {
    "hypr".source = ../../Hyprland;
    "kitty".source = ../../Kitty;
    "quickshell".source = ../../Quickshell;
    "uwsm/env-hyprland".source = ../../Hyprland/Uwsm/env-hyprland;

    # Not Hyprland-specific (Pacnix, Run, Reload, etc. are general-purpose),
    # so it's its own top-level folder/XDG dir, same pattern as the others.
    "scripts".source = ../../Scripts;

    # Same plain copy as everything else above. theme.py (run manually,
    # live -- see Scripts/Reload/theme.py) writes config.jsonc and
    # colors.env straight into Dotfiles/Fastfetch/; this just picks up
    # whatever's there at rebuild time, same as any other dotfile.
    "fastfetch".source = ../../Fastfetch;

    # Gwenview's canvas fill (app/gvcore.cpp) builds its palette from
    # KColorSchemeManager, reading the active .colors file directly -- not
    # qt6ct's palette at all. Stock BreezeDark has zero alpha anywhere in it,
    # so no color-scheme setting alone makes that fill translucent. This is
    # BreezeDark with alpha added to just [Colors:View] BackgroundNormal
    # (traced: with a dark scheme + Dark mode, gvcore.cpp uses that color
    # directly, no swap), used only by Gwenview via its own ColorScheme key.
    "gwenviewrc" = {
      force = true; # gwenview had already written its own copy imperatively;
                    # home-manager refuses to clobber existing files otherwise.
      text = ''
        [General]
        BackgroundColorMode=DocumentView::Dark

        [UiSettings]
        ColorScheme=BreezeDarkTransparent
      '';
    };
  };

  xdg.dataFile."color-schemes/BreezeDarkTransparent.colors".source = ../../Themes/Gwenview/BreezeDarkTransparent.colors;

  # Declarative Proton GE: symlinks nixpkgs' proton-ge-bin into Steam's compat
  # tools dir. Version is whatever nixpkgs pins; bumps on flake update + rebuild,
  # no protonup/imperative download step needed. Force-check the tool in
  # Properties > Compatibility after a version bump.
  xdg.dataFile."Steam/compatibilitytools.d/GE-Proton".source = pkgs.proton-ge-bin;
}