# &desc: "Desktop setup -- Dolphin menu (garcon xfce-applications.menu), udisks2, polkit, gvfs services."

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

  services.udisks2.enable = true;
  security.polkit.enable = true;
  services.gvfs.enable = true;

  # PipeWire audio stack -- no prior audio config existed in this repo at
  # all. rtkit is required for realtime scheduling (glitch-free audio);
  # pulse/alsa compat lets non-PipeWire-native apps keep working.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Per-game Steam launch options, e.g.:
  #   gamemoderun gamescope -f -r 144 -- mangohud %command%

  # All programs.* declarations (fish, hyprland, steam, gamemode, gamescope,
  # silentSDDM) now live in modules/packages/programs/programs.nix.
}