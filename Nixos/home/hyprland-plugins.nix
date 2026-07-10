{ config, pkgs, ... }:

# ---------------------------------------------------------------------------
# HOW TO ADD A PLUGIN
#
# 1. Get the commit + hash in one shot:
#
#      nix run nixpkgs#nix-prefetch-git -- \
#        --url <git-url> --quiet
#
#    Omit --rev to prefetch the default branch's HEAD; add --rev <sha> to
#    pin a specific commit instead. The JSON it prints has everything you
#    need:
#      "rev"    -> rev
#      "hash"   -> hash
#      "date"   -> first 10 chars ("YYYY-MM-DD") -> version's date part
#
# 2. Append one more mkPlugin { ... } block to `plugins` below using those
#    values. `version` defaults from `rev` if you don't want to bother
#    copying the date.
#
# 3. Rebuild. If the build fails looking for extra headers/libs, add the
#    missing nixpkgs package(s) to extraBuildInputs and rebuild again.
#
# Nothing outside this file needs to change -- Config/Apps/autostart.lua
# loads every .so that ends up in hypr-plugins/, whatever its name.
# ---------------------------------------------------------------------------

let
  # Builds a Hyprland plugin from git the same way nixpkgs' own
  # mkHyprlandPlugin does: against this system's pinned pkgs.hyprland, so the
  # plugin ABI always matches the compositor it loads into. Use this for any
  # plugin that isn't in nixpkgs' hyprlandPlugins set.
  mkPlugin =
    { name
    , url
    , rev
    , hash
    , version ? "0-unstable-${builtins.substring 0 8 rev}"
    , libFile ? "lib${name}.so"
    # Most plugins are CMake + pkg-config, hence the default -- but it's a
    # full override, not an addition: a meson-based plugin should set this
    # to [ pkgs.meson pkgs.ninja pkgs.pkg-config ] outright rather than
    # piling meson/ninja on top of cmake, which would leave two build
    # systems' setup hooks fighting over which configurePhase runs.
    , nativeBuildInputs ? [ pkgs.cmake pkgs.pkg-config ]
    , extraBuildInputs ? [ ]
    }:
    {
      inherit name libFile;
      drv = pkgs.hyprland.stdenv.mkDerivation {
        pname = "hyprland-${name}";
        inherit version nativeBuildInputs;

        src = pkgs.fetchgit { inherit url rev hash; };

        buildInputs = [ pkgs.hyprland ] ++ pkgs.hyprland.buildInputs ++ extraBuildInputs;

        dontStrip = true;
      };
    };

  plugins = [
    # ---- pacnix plugins <git-url> output goes here, one block per plugin ----

    (mkPlugin {
      name = "scrolloverview";
      url = "https://github.com/yayuuu/hyprland-scroll-overview.git";
      rev = "8b6d2b6943f82067febc4ecd6b4a73cb9bf8b3ba";
      hash = "sha256-5E1JlhrvH7sXt+zPCRGnb0f617IJe+FFqTlUN7Vw99Y=";
      version = "0-unstable-2026-07-07";
      extraBuildInputs = [ pkgs.lua5_4 pkgs.systemd ];
    })

    # ---- add more mkPlugin { ... } blocks above this line ----
  ];
in
{
  # Fixed, rebuild-stable paths (unlike each plugin's own /nix/store/<hash>-...
  # output) so Config/Apps/autostart.lua can `hyprctl plugin load` them
  # without needing to know the current store path.
  xdg.dataFile = builtins.listToAttrs (map
    (p: {
      name = "hypr-plugins/${p.name}.so";
      value.source = "${p.drv}/lib/${p.libFile}";
    })
    plugins);
}
