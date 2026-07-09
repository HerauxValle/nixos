{ config, pkgs, ... }:

{
  imports = [
    ./sudo-keyfile.nix
    ./usb-killswitch.nix
  ];
}
