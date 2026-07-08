{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ./modules/backup
    ./modules/boot
    ./modules/desktop
    ./modules/nix
    ./modules/packages
    ./modules/security
    ./modules/system
  ];

  system.stateVersion = "26.05";
}