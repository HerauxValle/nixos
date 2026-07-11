{ config, pkgs, ... }:

# installed.nix's package list has no schema/logic split at all -- it's
# purely personal, lives in Nixos/config/packages.nix instead.
{
  imports = [
    ./programs.nix
    ./scripts
    ./shells
  ];
}
