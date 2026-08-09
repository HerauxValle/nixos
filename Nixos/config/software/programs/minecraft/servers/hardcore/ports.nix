# &desc: "Hardcore server's port-forwarding entries -- raw MC TCP port, RCON (same net.ipv6=false raw-binary reasoning as creative/ports.nix), BlueMap's own web server, and MCPanel's web console."

{ ... }:

{
  # 8101, not BlueMap's default 8100 -- creative's BlueMap already owns
  # 8100 on this same host, see files.nix's matching webserver.port.
  vars.system.ports.entries.bluemapHardcore = {
    port = 8101;
    service = "minecraft-server-hardcore.service";
    mode.local.name = "bluemap.hardcore";
  };

  # 8091, not MCPanel's default 8090 -- filebrowser (self-hosted) already
  # owns 8090 on this host. Config file/key to change MCPanel's own
  # listen port wasn't confirmed, so this forwards 8091 -- check the
  # generated config after first boot and update MCPanel's own port to
  # match if it's still listening on 8090 by default.
  vars.system.ports.entries.mcpanelHardcore = {
    port = 8091;
    service = "minecraft-server-hardcore.service";
    mode.local.name = "mcpanel.hardcore";
  };

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
