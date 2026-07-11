{ config, pkgs, ... }:

{
  imports = [
    ./sudo-keyfile
    ./usb-killswitch
  ];
}
