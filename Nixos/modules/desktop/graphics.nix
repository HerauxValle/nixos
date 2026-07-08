{ config, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = false;
  hardware.graphics.enable = false;
  hardware.graphics.enable32Bit = true;
}