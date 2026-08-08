# &desc: "Creative server's package/version pin, enable/firewall toggles, and the restartIfChanged/stopIfChanged override so plugin-jar edits never restart the running server on rebuild."

{ pkgs, lib, ... }:

{
  # Rebuilds must never touch the running server on their own -- a plugin
  # jar edit changes this unit's derivation, and without this NixOS would
  # stop (world save across every world, 30-60s+) then restart it on every
  # single `pacnix rebuild`. Only explicit `systemctl start/stop
  # minecraft-server-creative` should ever do that now.
  systemd.services.minecraft-server-creative = {
    restartIfChanged = lib.mkForce false;
    stopIfChanged = lib.mkForce false;
  };

  services.minecraft-servers.servers.creative = {
    enable = false;

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
    jvmOpts = "-Xmx8G -Xms1G -Dpaper.disableChannelLimit=true";
  };
}
