# &desc: "System config imports -- autostart jobs, hidden devices, keyring setup, mountpoints, and port forwarding."

{ ... }:

{
  imports = [
    ./autostart.nix
    ./hidden-devices.nix
    ./keyring.nix
    ./mountpoints.nix
    ./ports.nix
  ];
}
