# &desc: "System config imports -- autostart jobs, hidden devices, keyring setup, mountpoints, openrazer, and port forwarding."

{ ... }:

{
  imports = [
    ./autostart.nix
    ./hidden-devices.nix
    ./keyring.nix
    ./mountpoints.nix
    ./openrazer.nix
    ./ports.nix
  ];
}
