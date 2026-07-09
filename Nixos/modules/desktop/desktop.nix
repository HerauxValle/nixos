{ config, pkgs, ... }:

let
  # Path to an image to use as the SDDM login/lock background, or null to
  # leave the theme's own stock background (configs/default.conf's
  # smoky.jpg) in place instead of overriding it.
  wallpaper = ../../../Scripts/Wallpaper/wallpaper.jpg;
  # wallpaper = null;
in

{
  # Config/Apps/autostart.lua already runs, every Hyprland session, on line 31:
  #   prefix=$(ls /etc/xdg/menus/ | grep -m1 "applications.menu$" | sed 's/applications.menu$//')
  #   XDG_MENU_PREFIX=${prefix:-} kbuildsycoca6 --noincremental
  # ported straight from the working Arch setup. It auto-detects whatever
  # *-applications.menu the distro ships (Arch ships arch-applications.menu)
  # and rebuilds sycoca with the matching prefix on every login. NixOS ships
  # no such file at all, so that script has always had nothing to find here
  # -- this is the one missing piece, not a new mechanism. Using garcon's
  # (XFCE) copy since it's a plain generic menu, not Plasma's KDE-specific
  # hand-curated one that produced the duplicate/miscategorized entries.
  environment.etc."xdg/menus/nixos-applications.menu".source =
    "${pkgs.garcon}/etc/xdg/menus/xfce-applications.menu";

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