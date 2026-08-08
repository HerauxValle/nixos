# &desc: "Hardcore Minecraft server -- survival, one life, port 25565. Disabled until the Minecraft vault exists (see autostart.nix)."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore = {

    # Toggled on as its active at this point in time
    enable = false;

    # The minecraft module itself does not expose anything above v1.21.9
    # nix-minecraft is essential to play the latest version here!
    package = pkgs.paperServers.paper-26_1_2;

    # Enabled for non-local access from the same network
    openFirewall = true;

    serverProperties = {
      server-port = 25565;
      gamemode = "survival"; # fallback/default world gamemode
      difficulty = "hard"; # fallback difficulty
      hardcore = false; # DO NOT set true here — Multiverse sets it per-world instead
      motd = "...";
      level-name = "world"; # your default/hub world
      online-mode = true; # keep true unless you have a specific reason not to
      white-list = false; # or true if you want to gate join access
      pvp = true;
      view-distance = 32;
      simulation-distance = 12;
    };

    # TEMP: both plugins commented out to isolate "Invalid custom payload
    # payload!" on join -- suspect one of them is corrupting the vanilla
    # minecraft:register plugin-channel handshake on this very new MC
    # version. Re-enable once confirmed innocent/guilty.
    # symlinks = {
    #   "plugins/Multiverse-Core.jar" = pkgs.fetchurl {
    #     url = "https://github.com/Multiverse/Multiverse-Core/releases/download/5.7.3/multiverse-core-5.7.3.jar";
    #     hash = "sha256-yRp8LCWtfYeCV7CMmAOB6LX/uo32P69AIkK/tWoFiIQ=";
    #   };
    #   "plugins/BlueMap.jar" = pkgs.fetchurl {
    #     url = "https://cdn.modrinth.com/data/swbUV1cr/versions/K5U1ASjn/bluemap-5.23-paper.jar";
    #     hash = "sha256-M5VU11ztqzVON2Z3z8cwjEmZUpFYSejimUcY5KFT1k4=";
    #   };
    # };
    #
    # files."plugins/BlueMap/core.conf" = {
    #   format = pkgs.formats.json { };
    #   value = {
    #     accept-download = true;
    #   };
    # };
  };

  # openFirewall above only opens serverProperties.server-port (25565) --
  # BlueMap's own web server (core.conf webserver.port, default 8100) needs
  # its own opening, wired through the same port-forwarding module every
  # self-hosted service uses (see config/system/ports.nix).
  vars.system.ports.entries.bluemap = {
    port = 8100;
    service = "minecraft-server-hardcore.service";
    mode.local.name = "bluemap";
  };

  # mDNS name only -- the module's resolveUrl port-stripping (bare
  # http://name.local with no port) is an HTTP-only reverse proxy on
  # 80/443 (see modules/system/port-forwarding/lib/router/), which
  # doesn't apply to Minecraft's raw TCP protocol. The MC client still
  # needs the port typed explicitly: hardcore.local:25565.
  #
  # net.ipv6 = false is required, not optional: the default IPv6 bridge
  # (lib/ipv6-bridge/) defaults to tls.mode = "http/s", an HTTP-aware
  # relay that parses request lines/TLS-sniffs the stream -- it silently
  # corrupted Minecraft's raw binary handshake ("Invalid custom payload
  # payload!" on connect) whenever a client happened to reach it over
  # IPv6. Disabling the bridge leaves ipv4 as a plain firewall ACCEPT
  # with no protocol inspection at all, which is what a raw TCP service
  # like this actually needs.
  vars.system.ports.entries.hardcore = {
    port = 25565;
    service = "minecraft-server-hardcore.service";
    mode.local.name = "hardcore";
    net.ipv6 = false;
  };
}
