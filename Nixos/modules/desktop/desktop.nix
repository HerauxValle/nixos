{ config, pkgs, ... }:

let
  # Path to an image to use as the SDDM login/lock background, or null to
  # leave the theme's own stock background (configs/default.conf's
  # smoky.jpg) in place instead of overriding it.
  wallpaper = ../../../Scripts/Wallpaper/wallpaper.jpg;
  # wallpaper = null;
in

{
  # Dolphin's "Open With" dialog calls the org.freedesktop.impl.portal.desktop.kde
  # D-Bus service to render its application picker (KDE bug 466148). Only the
  # gtk and hyprland portal backends are installed here, so that call fails
  # silently and the dialog is blank for every file. Add the kde backend.
  xdg.portal.extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];

  services.udisks2.enable = false;
  security.polkit.enable = false;
  services.gvfs.enable = false;
  programs.fish.enable = false;

  programs.hyprland = {
    enable = false;
    withUWSM = true;
    xwayland.enable = false;
  };

  programs.steam = {
    enable = false;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    localNetworkGameTransfers.openFirewall = true;
  };

  # Bumps CPU governor/priority while a game runs. Use via `gamemoderun %command%` in Steam launch options.
  programs.gamemode.enable = false;
  # Micro-compositor for FSR upscaling / frame limiting / fullscreen fixes. Use via `gamescope ... -- %command%`.
  programs.gamescope.enable = false;

  # Per-game Steam launch options to combine all three above, e.g.:
  #   gamemoderun gamescope -f -r 144 -- mangohud %command%

  # Sets up services.displayManager.sddm itself (theme, wayland.enable,
  # extraPackages etc.) -- see flake.nix for the silent-sddm input.
  programs.silentSDDM = {
    enable = false;
    theme = "default";

    # Filename after copy is the basename of the wallpaper path, regardless
    # of this attrset key -- see silent-sddm's nix/package.nix.
    backgrounds = if wallpaper == null then { } else { inherit wallpaper; };

    settings =
      if wallpaper == null then
        { }
      else
        {
          "LoginScreen".background = builtins.baseNameOf wallpaper;
          "LockScreen".background = builtins.baseNameOf wallpaper;
        };
  };
}