# &desc: "NVIDIA graphics configuration -- open=false, modesetting=true, 32-bit support enabled."

{ config, pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = false;
  hardware.nvidia.modesetting.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
}