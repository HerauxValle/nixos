# &desc: "Hyprland plugin builder (mkPlugin) -- builds from git or a local path against pinned pkgs.hyprland for ABI match, CMake/Meson/Makefile configurable."

{ config, pkgs, lib, ... }:

let
  # Builds a Hyprland plugin from git the same way nixpkgs' own
  # mkHyprlandPlugin does: against this system's pinned pkgs.hyprland, so the
  # plugin ABI always matches the compositor it loads into. Use this for any
  # plugin that isn't in nixpkgs' hyprlandPlugins set.
  mkPlugin =
    { name
    , url ? null
    , rev ? null
    , hash ? null
    # Local, path-based source for a first-party plugin living in this repo
    # (e.g. ../../../../Hyprland/plugins/canvas) -- skips fetchgit entirely
    # while still building against pkgs.hyprland.stdenv, so ABI stays
    # matched to the exact locally-pinned Hyprland. Deliberately not wired
    # through a second flake input the way Scripts/LTree/Casket/CRun are
    # consumed: a second nixpkgs pin here could drift from this system's
    # actual pkgs.hyprland and reintroduce an ABI mismatch.
    , src ? null
    , version ? "0-unstable-${builtins.substring 0 8 (if rev != null then rev else "local")}"
    , libFile ? "lib${name}.so"
    # Most plugins are CMake + pkg-config, hence the default -- but it's a
    # full override, not an addition: a meson-based plugin should set this
    # to [ pkgs.meson pkgs.ninja pkgs.pkg-config ] outright rather than
    # piling meson/ninja on top of cmake, which would leave two build
    # systems' setup hooks fighting over which configurePhase runs.
    , nativeBuildInputs ? [ pkgs.cmake pkgs.pkg-config ]
    , extraBuildInputs ? [ ]
    # Plain-Makefile plugins (no CMake/meson project file) need their own
    # install step -- their upstream `make install` often does something
    # nix-inappropriate (e.g. calling `hyprctl plugin load` directly, which
    # needs a running compositor that doesn't exist in the build sandbox).
    # Leave null to keep the default `make install` behaviour CMake/meson
    # projects already rely on.
    , installPhase ? null
    }:
    assert src != null || (url != null && rev != null && hash != null); # need a source: local path, or url+rev+hash
    {
      inherit name libFile;
      drv = pkgs.hyprland.stdenv.mkDerivation ({
        pname = "hyprland-${name}";
        inherit version nativeBuildInputs;

        src = if src != null then src else pkgs.fetchgit { inherit url rev hash; };

        buildInputs = [ pkgs.hyprland ] ++ pkgs.hyprland.buildInputs ++ extraBuildInputs;

        dontStrip = true;
      } // lib.optionalAttrs (installPhase != null) { inherit installPhase; });
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
