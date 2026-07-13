{ config, pkgs, ... }:

{
  imports = [
    ./mountpoints
    ./networking.nix
    ./port-forwarding
    ./users
  ];
}
