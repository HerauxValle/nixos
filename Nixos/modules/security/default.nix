
# &desc: "Security modules -- passwordless sudo via keyfile on USB, USB removal hard/soft/disabled power-off trigger, and personal GitHub auth/sign SSH key deployment."

{ config, pkgs, ... }:

{
  imports = [
    ./github-keys.nix
    ./sudo-keyfile
    ./usb-killswitch
  ];
}
