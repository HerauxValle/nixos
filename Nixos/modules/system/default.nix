# &desc: "System module schema -- imports acl-grants, autostart, bluetooth, storage mounts, networking, port forwarding, device hiding, openrazer, power, swap, and users submodules."

{ config, pkgs, ... }:

{
  imports = [
    ./acl-grants.nix
    ./autostart
    ./bluetooth.nix
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
