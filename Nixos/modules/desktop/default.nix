{ config, pkgs, ... }:

{
  imports = [
    ./desktop.nix
    ./graphics.nix
    ./theming.nix
  ];
}
