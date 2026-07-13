{ config, pkgs, ... }:

{
  networking.hostName = config.vars.hostName;
  networking.networkmanager.enable = false;
  # Pinned deliberately, not the hardware default -- see local notes for why.
  networking.interfaces.${config.vars.networkInterface}.macAddress = null;
  time.timeZone = config.vars.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fr";
  services.xserver.xkb.layout = "fr";
}