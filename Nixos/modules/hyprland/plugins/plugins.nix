# &desc: "Hyprland plugin builder (mkPlugin) -- builds from git against pinned pkgs.hyprland for ABI match, CMake/Meson configurable."

{ config, pkgs, ... }:

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

  plugins = map mkPlugin config.vars.hyprland.hyprlandPlugins;
in
{
  # Fixed, rebuild-stable paths (unlike each plugin's own /nix/store/<hash>-...
  # output) so Config/Apps/autostart.lua can `hyprctl plugin load` them
  # without needing to know the current store path.
  home-manager.users.${config.vars.identity.username}.xdg.dataFile = builtins.listToAttrs (map
    (p: {
      name = "hypr-plugins/${p.name}.so";
      value.source = "${p.drv}/lib/${p.libFile}";
    })
    plugins);
}
