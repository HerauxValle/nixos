{ config, pkgs, ... }:

{
  networking.hostName = config.vars.identity.hostName;
  networking.networkmanager.enable = false;
  # Pinned deliberately, not the hardware default -- see local notes for why.
  networking.interfaces.${config.vars.identity.networkInterface}.macAddress = null;
  time.timeZone = config.vars.identity.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fr";
  services.xserver.xkb.layout = "fr";
}