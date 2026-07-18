# &desc: "NVIDIA graphics configuration -- open=false, modesetting=true, 32-bit support enabled."

{ config, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = false;
  hardware.graphics.enable = false;
  hardware.graphics.enable32Bit = true;
}