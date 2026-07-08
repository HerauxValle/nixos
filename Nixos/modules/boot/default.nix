{ config, pkgs, ... }:

{
  imports = [
    ./grub.nix
    ./luks2.nix
  ];
}