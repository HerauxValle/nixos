{ config, pkgs, ... }:

{
  imports = [

    ./grub
    ./luks2
    ./usb-required

  ];
}
