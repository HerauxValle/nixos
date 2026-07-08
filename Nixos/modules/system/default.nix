{ config, pkgs, ... }:

{
  imports = [
    ./networking.nix
    ./users.nix
  ];
}
