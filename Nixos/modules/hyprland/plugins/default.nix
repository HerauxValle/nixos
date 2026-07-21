# &desc: "Hyprland plugins schema with building docs -- raw specs (name/url/rev/hash), personal picks, build logic in ./plugins.nix."

{ pkgs, lib, ... }:

# Which Hyprland plugins to build, raw specs (name/url/rev/hash/...) --
# entirely personal, same as config/scripts.nix's picks, but this one
# already ships as part of the base setup, so it lives here as a real
# definition rather than in config/. Building logic (mkPlugin) lives in
# ./plugins.nix, imported below.
#
# HOW TO ADD ANOTHER PLUGIN
#
# 1. Get the commit + hash in one shot:
#
#      nix run nixpkgs#nix-prefetch-git -- \
#        --url <git-url> --quiet
#
#    Omit --rev to prefetch the default branch's HEAD; add --rev <sha> to
#    pin a specific commit instead. The JSON it prints has everything you
#    need: "rev" -> rev, "hash" -> hash, "date" (first 10 chars) -> the
#    date part of version.
#
# 2. Append one more record to config.vars.hyprland.hyprlandPlugins below using
#    those values. `version` isn't required -- mkPlugin defaults it from
#    rev if you don't want to bother copying the date.
#
# 3. Rebuild. If the build fails looking for extra headers/libs, add the
#    missing nixpkgs package(s) to that record's extraBuildInputs and
#    rebuild again.
{
  imports = [ ./plugins.nix ];

  options.vars.hyprland.hyprlandPlugins = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = [ ];
    description = "Raw Hyprland plugin specs (name/url/rev/hash/...) -- built and loaded by ./plugins.nix.";
  };

  config.vars.hyprland.hyprlandPlugins = [

    # -------------------------------------------------------------------------
    # ---- add more plugin records above this line ----------------------------
    # -------------------------------------------------------------------------

    {
      # First-party: infinite canvas per workspace (each workspace is its own
      # pannable/zoomable 2D space, floating windows placed anywhere in it
      # like nodes on a ComfyUI canvas). Local source, not fetched -- see
      # ../../../../Hyprland/plugins/canvas/DESIGN.md for the architecture
      # and why hypr-canvas (the third-party plugin this replaces) didn't
      # work here.
      name = "canvas";
      src = ../../../../Hyprland/plugins/canvas;
      version = "0-unstable-local";
      libFile = "canvas.so"; # Makefile's OUT has no "lib" prefix
      nativeBuildInputs = [ pkgs.pkg-config ]; # plain Makefile, no CMake
    }

    {
      name = "scrolloverview";
      url = "https://github.com/yayuuu/hyprland-scroll-overview.git";
      rev = "8b6d2b6943f82067febc4ecd6b4a73cb9bf8b3ba";
      hash = "sha256-5E1JlhrvH7sXt+zPCRGnb0f617IJe+FFqTlUN7Vw99Y=";
      version = "0-unstable-2026-07-07";
      extraBuildInputs = [ pkgs.lua5_4 pkgs.systemd ];
    }

  ];
}
