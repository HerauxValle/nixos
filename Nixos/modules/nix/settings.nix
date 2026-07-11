{ config, pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # programs.nix-ld now lives in modules/packages/programs/programs.nix.
}