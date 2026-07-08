{ config, pkgs, ... }:

{
  networking.hostName = "nixos";
  networking.networkmanager.enable = false;
  # Spoof to the "Alexa" MAC recorded in Backups/Drive/Internet.txt — the ISP
  # prioritizes this MAC for bandwidth/QoS regardless of the old device rules.
  networking.interfaces.enp3s0.macAddress = "*****************";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fr";
  services.xserver.xkb.layout = "fr";
}