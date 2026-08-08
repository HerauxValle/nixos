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

    # Paper caps the number of plugin channels a client can register in
    # one handshake -- with a 100+ mod Fabric client (many of which
    # register their own Fabric API networking channels), that cap gets
    # exceeded, and Paper kicks with "Invalid custom payload payload!"
    # on join (confirmed: reproduced with zero server plugins too, so it
    # wasn't Multiverse-Core/BlueMap). This flag removes the cap.
    jvmOpts = "-Xmx8G -Xms1G -Dpaper.disableChannelLimit=true";

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

    symlinks = {
      "plugins/Multiverse-Core.jar" = pkgs.fetchurl {
        url = "https://github.com/Multiverse/Multiverse-Core/releases/download/5.7.3/multiverse-core-5.7.3.jar";
        hash = "sha256-yRp8LCWtfYeCV7CMmAOB6LX/uo32P69AIkK/tWoFiIQ=";
      };
      "plugins/BlueMap.jar" = pkgs.fetchurl {
        url = "https://cdn.modrinth.com/data/swbUV1cr/versions/K5U1ASjn/bluemap-5.23-paper.jar";
        hash = "sha256-M5VU11ztqzVON2Z3z8cwjEmZUpFYSejimUcY5KFT1k4=";
      };
      # Auto-links each world-group's own nether/end by naming convention
      # (world -> world_nether/world_end, creative -> creative_nether/
      # creative_the_end, etc.) -- no per-world config needed, since a
      # player-built portal in "creative" should never send them to
      # hardcore's nether, and vice versa.
      "plugins/Multiverse-NetherPortals.jar" = pkgs.fetchurl {
        url = "https://cdn.modrinth.com/data/vtawPsTo/versions/RRa80eDI/multiverse-netherportals-5.1.0.jar";
        hash = "sha256-pLN1CXC1txCqlCuq/weo/O9WgCzyhrnc2n5p3ZBEksw=";
      };
    };

    files."plugins/BlueMap/core.conf" = {
      format = pkgs.formats.json { };
      value = {
        accept-download = true;
      };
    };

    # Shown in the client's multiplayer server list -- must be exactly 64x64.
    files."server-icon.png" = ../icons/hardcore.png;

    # Always spawn in the void "hub" world on every join (not just first
    # ever join) -- a native Multiverse-Core feature, no extra plugin
    # needed. Partial override: Multiverse backfills every other key in
    # this file with its own defaults on load, same as BlueMap's
    # core.conf above.
    files."plugins/Multiverse-Core/config.yml".value = {
      spawn = {
        enable-join-destination = true;
        join-destination = "hub";
      };
    };

    # /hub as a manual way back, on top of the automatic every-join spawn
    # above -- aliases to Multiverse-Core's own self-teleport command.
    files."commands.yml".value = {
      aliases = {
        hub = [ "mvtp hub" ];
      };
    };

    # Declarative world creation -- guarded by checking each world's
    # folder on disk, so this is a no-op after the first successful run
    # (world data itself persists in dataDir like any other save, this
    # is only what recreates it if the vault were ever wiped). Runs
    # inside the same service unit as the server itself (WorkingDirectory
    # = dataDir/hardcore already, ProtectHome/PrivateUsers already
    # relaxed below), sent over the same tmux console socket used for
    # `/mv` commands live during initial setup.
    #
    # A fixed sleep instead of polling the log for "Done (" -- tried that
    # first, but latest.log's rotation timing (old file -> dated .log.gz,
    # fresh empty file) races against ExecStartPost's own start (fires the
    # instant the tmux-wrapped start script *returns*, near-instant under
    # Type=forking, well before Paper/Multiverse actually finish booting
    # inside that session). Capturing a line-count offset before rotation
    # lands means the offset never gets reached again, so the poll just
    # burns its full timeout every time. Not worth chasing further: Paper
    # boots in ~8s in practice and Multiverse's own create command is
    # idempotent (harmlessly logs "already exists" if this fires early on
    # a world that's already there), so a generous flat sleep is simpler
    # and just as correct.
    extraStartPost = ''
      SOCK="/run/minecraft/hardcore.sock"
      send() { ${pkgs.tmux}/bin/tmux -S "$SOCK" send-keys "$1" Enter; }
      sleep 20

      [ -d creative ] || send 'mv create creative normal -t flat --generator-settings {"layers":[{"block":"minecraft:white_stained_glass","height":1}],"biome":"minecraft:plains"}'
      sleep 3
      [ -d creative_nether ] || send "mv create creative_nether nether"
      sleep 3
      [ -d creative_the_end ] || send "mv create creative_the_end the_end"
      sleep 3
      [ -d hub ] || send 'mv create hub normal -t flat --generator-settings {"layers":[],"biome":"the_void"}'
    '';
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
