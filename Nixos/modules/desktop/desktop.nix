{ config, pkgs, ... }:

{
  # Dolphin's own log (journalctl --user -t dolphin), every single time it's
  # been checked in this session, shows it searching for the plain,
  # unprefixed "applications.menu" -- never a prefixed variant. (The
  # autostart script's XDG_MENU_PREFIX=nixos- only applies to its own
  # one-off kbuildsycoca6 subprocess, not to Dolphin's environment, so a
  # prefixed filename doesn't help Dolphin's own lookup.) NixOS ships no
  # applications.menu at all; using garcon's (XFCE) generic one, not
  # Plasma's KDE-specific hand-curated one that caused duplicate entries.
  environment.etc."xdg/menus/applications.menu".source =
    "${pkgs.garcon}/etc/xdg/menus/xfce-applications.menu";

  services.udisks2.enable = false;
  security.polkit.enable = false;
  services.gvfs.enable = false;

  # Per-game Steam launch options, e.g.:
  #   gamemoderun gamescope -f -r 144 -- mangohud %command%

  # All programs.* declarations (fish, hyprland, steam, gamemode, gamescope,
  # silentSDDM) now live in modules/packages/programs.nix.
}