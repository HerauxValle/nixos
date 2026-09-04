# &desc: "System module schema -- imports acl-grants, autostart, bluetooth, ddc, storage mounts, networking, port forwarding, device hiding, openrazer, gamepad-bridge, power, swap, and users submodules."

{ config, pkgs, ... }:

{
  imports = [
    ./acl-grants.nix
    ./autostart
    ./bluetooth.nix
    ./ddc.nix
    ./gamepad-bridge.nix
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
