{ config, pkgs, ... }:

{
  imports = [
    ./installed.nix
    ./programs.nix
    ./scripts.nix
    ./shells.nix
  ];
}
