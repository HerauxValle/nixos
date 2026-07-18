
{ config, pkgs, ... }:

{
  imports = [
    ./autostart
    ./hidden-devices.nix
    ./mountpoints
    ./networking.nix
    ./port-forwarding
    ./users
  ];
}
