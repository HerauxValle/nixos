# &desc: "System module schema -- imports autostart, storage mounts, networking, port forwarding, device hiding, and users submodules."

{ config, pkgs, ... }:

{
  imports = [
    ./autostart
    ./hidden-devices.nix
    ./mountpoints
    ./networking.nix
    ./port-forwarding
    ./users
  ];
}
