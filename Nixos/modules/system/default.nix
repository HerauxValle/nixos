# &desc: "System module schema -- imports acl-grants, autostart, storage mounts, networking, port forwarding, device hiding, openrazer, power, swap, and users submodules."

{ config, pkgs, ... }:

{
  imports = [
    ./acl-grants.nix
    ./autostart
    ./hidden-devices.nix
    ./mountpoints
    ./networking.nix
    ./openrazer.nix
    ./port-forwarding
    ./power.nix
    ./swap
    ./users
  ];
}
