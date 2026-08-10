# &desc: "Creative server's package/version pin, enable/firewall toggles, and the TimeoutStartSec bump for its slow multi-world ExecStartPost."

{ pkgs, lib, ... }:

{
  # restartIfChanged/stopIfChanged = false is now generic across every
  # server (settings.nix's genAttrs block) instead of duplicated per
  # server here -- see that file's own comment.
  systemd.services.minecraft-server-creative = {
    # Type=forking only reports "active" once ExecStartPost fully exits --
    # with 4 world-groups (10 dimensions total) that script runs a 40s
    # startup-race-safety sleep (see minecraft-worlds.nix's mkServerScript)
    # plus ~3-4s per dimension for /mv create, easily 80s+ end to end.
    # The default 90s TimeoutStartSec was too tight for that: confirmed
    # in the wild 2026-08-08, it killed ExecStartPost mid-run and
    # Restart=always looped the server through repeated failed boots.
    serviceConfig.TimeoutStartSec = lib.mkForce "5min";
  };

  services.minecraft-servers.servers.creative = {
    enable = true;

    # The minecraft module itself does not expose anything above v1.21.9
    # nix-minecraft is essential to play the latest version here!
    #
    # Several plugins (Axiom, HeadDB's newest, this server's plugin
    # ecosystem generally) increasingly only target 26.2. Your Prism
    # client stays pinned to 26.1.2 -- bridge the gap with ViaFabricPlus
    # client-side (its actual intended purpose: connecting to a server on
    # a different protocol version), not by updating the whole 100+ mod pack.
    package = pkgs.paperServers.paper-26_2;

    # Enabled for non-local access from the same network
    openFirewall = true;

    # Paper caps the number of plugin channels a client can register in
    # one handshake -- with a 100+ mod Fabric client (many of which
    # register their own Fabric API networking channels), that cap gets
    # exceeded, and Paper kicks with "Invalid custom payload payload!"
    # on join (confirmed: reproduced with zero server plugins too, so it
    # wasn't Multiverse-Core/BlueMap). This flag removes the cap.
    jvmOpts = "-Xmx4G -Xms1G -Dpaper.disableChannelLimit=true";
  };
}
