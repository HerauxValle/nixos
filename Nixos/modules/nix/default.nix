
{ config, pkgs, ... }:

{
  imports = [
    ./gc.nix
    ./optimise.nix
    ./settings.nix
  ];
}
