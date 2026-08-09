# &desc: "Hardcore server's port-forwarding entries -- raw MC TCP port and RCON, same net.ipv6=false raw-binary reasoning as creative/ports.nix."

{ ... }:

{
  vars.system.ports.entries.hardcore = {
    port = 25566;
    service = "minecraft-server-hardcore.service";
    mode.local.name = "hardcore";
    net.ipv6 = false; # raw TCP handshake -- the default IPv6 bridge is HTTP-aware and corrupts it
  };

  vars.system.ports.entries.hardcoreRcon = {
    port = 25576;
    service = "minecraft-server-hardcore.service";
    mode.local.name = "hardcore-rcon";
    net.ipv6 = false;
  };
}
