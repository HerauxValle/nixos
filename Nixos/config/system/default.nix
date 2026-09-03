# &desc: "System config imports -- ACL grants, autostart jobs, hidden devices, keyring setup, inputplumber, mountpoints, openrazer, port forwarding, and swap."

{ ... }:

{
  imports = [
    ./acl-grants.nix
    ./autostart.nix
    ./hidden-devices.nix
    ./inputplumber.nix
    ./keyring.nix
    ./mountpoints.nix
    ./openrazer.nix
    ./ports.nix
    ./swap.nix
  ];
}
