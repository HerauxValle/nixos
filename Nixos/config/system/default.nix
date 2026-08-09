# &desc: "System config imports -- autostart jobs, hidden devices, keyring setup, mountpoints, openrazer, port forwarding, and swap."

{ ... }:

{
  imports = [
    ./autostart.nix
    ./hidden-devices.nix
    ./keyring.nix
    ./mountpoints.nix
    ./openrazer.nix
    ./ports.nix
    ./swap.nix
  ];
}
