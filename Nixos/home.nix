{ config, pkgs, ... }:

{
  home.stateVersion = "26.05";
  home.username = "maxmustermann";
  home.homeDirectory = "/home/herauxvalle";

  imports = [
    ./home/apps.nix
    ./home/shells.nix
    ./home/theming.nix
  ];

  programs.home-manager.enable = false;
}