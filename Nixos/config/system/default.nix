# &desc: "System config imports -- ACL grants, autostart jobs, hidden devices, keyring setup, mountpoints, openrazer, port forwarding, sc-controller, and swap."

{ ... }:

{
  imports = [
    ./acl-grants.nix
    ./autostart.nix
    ./hidden-devices.nix
    ./keyring.nix
    ./mountpoints.nix
    ./openrazer.nix
    ./ports.nix
    ./sc-controller.nix
    ./swap.nix
  ];
}
