
# &desc: "Security modules -- passwordless sudo via keyfile on USB, and USB removal hard/soft/disabled power-off trigger."

{ config, pkgs, ... }:

{
  imports = [
    ./sudo-keyfile
    ./usb-killswitch
  ];
}
