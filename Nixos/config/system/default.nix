# &desc: "System config imports -- ACL grants, autostart jobs, ddc, gamepad-bridge, hidden devices, keyring setup, mountpoints, openrazer, port forwarding, and swap."

{ ... }:

{
  imports = [
    ./acl-grants.nix
    ./autostart.nix
    ./ddc.nix
    ./gamepad-bridge.nix
    ./hidden-devices.nix
    ./keyring.nix
    ./mountpoints.nix
    ./openrazer.nix
    ./ports.nix
    ./swap.nix
  ];
}
