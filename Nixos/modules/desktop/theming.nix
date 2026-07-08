{ config, pkgs, ... }:

{
  environment.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";  # fixed from stale "kde" value
  };

  # MyBar's icons are all "Symbols Nerd Font Mono" glyphs (see
  # Quickshell/MyBar's font.family references) — without this they render as
  # tofu boxes. No fonts.packages module existed at all before this.
  fonts.packages = [ pkgs.nerd-fonts.symbols-only ];
}