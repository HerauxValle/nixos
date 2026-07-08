{ config, pkgs, ... }:

{
  imports = [
    ./sudo-keyfile.nix
  ];
}
