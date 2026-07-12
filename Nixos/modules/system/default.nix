{ config, pkgs, ... }:

{
  imports = [
    ./mountpoints
    ./networking.nix
    ./users
  ];
}
