{ config, pkgs, ... }:

{
  imports = [
    ./autostart
    ./mountpoints
    ./networking.nix
    ./port-forwarding
    ./users
  ];
}
