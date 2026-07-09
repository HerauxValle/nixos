{ config, pkgs, ... }:

let
  # https://github.com/yayuuu/hyprland-scroll-overview -- niri-style workspace
  # overview. Not in nixpkgs' hyprlandPlugins set, so built by hand the same
  # way nixpkgs' own mkHyprlandPlugin does: against this system's pinned
  # pkgs.hyprland, so the plugin ABI always matches the compositor it loads
  # into. Bump rev/hash together when updating.
  scrolloverview = pkgs.hyprland.stdenv.mkDerivation {
    pname = "hyprland-scrolloverview";
    version = "0-unstable-2026-07-07";

    src = pkgs.fetchgit {
      url = "https://github.com/yayuuu/hyprland-scroll-overview.git";
      rev = "8b6d2b6943f82067febc4ecd6b4a73cb9bf8b3ba";
      hash = "sha256-5E1JlhrvH7sXt+zPCRGnb0f617IJe+FFqTlUN7Vw99Y=";
    };

    nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];
    buildInputs = [ pkgs.hyprland ] ++ pkgs.hyprland.buildInputs ++ [
      pkgs.lua5_4
      pkgs.systemd
    ];

    dontStrip = true;
  };
in
{
  # Fixed, rebuild-stable path (unlike the plugin's own /nix/store/<hash>-...
  # output) so Config/Apps/autostart.lua can `hyprctl plugin load` it without
  # needing to know the current store path.
  xdg.dataFile."hypr-plugins/scrolloverview.so".source =
    "${scrolloverview}/lib/libscrolloverview.so";
}
