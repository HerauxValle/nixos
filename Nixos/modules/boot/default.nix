# &desc: "Boot configuration -- GRUB theming, LUKS2 on VirtualKeys USB, and USB-required boot enforcement."

{ config, pkgs, ... }:

{
  imports = [

    ./grub
    ./luks2
    ./usb-required

  ];
}
