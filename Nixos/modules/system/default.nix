# &desc: "System module schema -- imports autostart, storage mounts, networking, port forwarding, device hiding, openrazer, swap, and users submodules."

{ config, pkgs, ... }:

{
  imports = [
    ./autostart
    ./hidden-devices.nix
    ./mountpoints
    ./networking.nix
    ./openrazer.nix
    ./port-forwarding
    ./swap
    ./users
  ];
}
