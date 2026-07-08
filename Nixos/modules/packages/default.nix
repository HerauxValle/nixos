{ config, pkgs, ... }:

{
  imports = [
    ./installed.nix
    ./scripts.nix
    ./shells.nix
  ];
}
