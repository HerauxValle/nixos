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
      # Only affects the ONE vanilla-bootstrapped default world ("world")
      # at first-ever boot -- Multiverse-created worlds (hub, creative)
      # go through a different code path entirely and are never affected
      # by this, regardless of its value. Multiverse-Core 5.x also has no
      # "hardcore" world property of its own to set this per-world after
      # the fact (checked: not in its 25-field world-properties list),
      # so this global flag is genuinely the only way to get it onto
      # "world" specifically.
      hardcore = true;
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
      # "disable_console" (not "disable") -- players still get the usual
      # /mv confirm prompt for their own destructive commands, only the
      # extraStartPost script below (running over the server console, not
      # as a player) skips it, needed for regenerate = true worlds' /mv
      # delete to run unattended.
      command.confirm-mode = "disable_console";
    };

    # /hub as a manual way back, on top of the automatic every-join spawn
    # above -- aliases to Multiverse-Core's own self-teleport command.
    files."commands.yml".value = {
      aliases = {
        hub = [ "mvtp hub" ];
      };
    };

  };

  # Declarative world creation -- schema + logic in
  # modules/services/minecraft-worlds/, generates each group's /mv create
  # console command(s) into services.minecraft-servers.servers.<server>.
  # extraStartPost, one entry per world-group (not per dimension) --
  # nether/end are just flags on the group they belong to.
  vars.minecraft.worlds = {
    # The original hardcore world -- vanilla auto-generates "world"/
    # "world_nether"/"world_end" at first boot regardless of this entry
    # (Multiverse just auto-imports them), but it's listed here too for
    # symmetry with the other groups; the idempotent [ -d ... ] guard
    # makes it a harmless no-op either way.
    world = {
      server = "hardcore";
      nether = true;
      end = true;
      # gamemode left null -- Multiverse's own default (survival), and
      # enforce-gamemode/enforce-flight (both true by default) mean
      # there's simply no creative/flight access here at all.
      #
      # hardcore = true here is the REAL enforcement (Skript ban-on-death,
      # see world-type.nix) -- serverProperties.hardcore = true above is
      # belt-and-suspenders on top of it (locks difficulty to hard,
      # vanilla's own spectator-lock-on-death for whichever world happens
      # to be the server's bootstrap default), not load-bearing by
      # itself. Unlike that server-wide flag, this one works on any
      # number of worlds, not just the one bootstrap default.
      hardcore = true;
    };

    creative = {
      server = "hardcore";
      worldType = "flat";
      generatorSettings = ''{"layers":[{"block":"minecraft:white_stained_glass","height":1}],"biome":"minecraft:plains"}'';
      nether = true;
      end = true;
      gamemode = "creative";
    };

    hub = {
      server = "hardcore";
      worldType = "flat";
      generatorSettings = ''{"layers":[],"biome":"the_void"}'';
      gamemode = "creative"; # so you can fly instead of falling into the void
      # No nether/end -- overworld-only lobby, per the original design.
    };
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
