# &desc: "Hardcore server's config-file overrides -- server-icon, BlueMap's accept-download + fog-of-war (min-inhabited-time) + full cave removal (remove-caves-below-y), and paper-global.yml's chunk-system IO thread count (pure disk-I/O throughput, zero gameplay effect)."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore.files = {
    "server-icon.png" = ../../icons/hardcore.png;

    # Purely how many threads handle chunk disk I/O -- no gameplay
    # behavior change at all, just throughput. Default is -1 (single
    # thread); worker-threads (chunk generation parallelism) left
    # unset/default since its auto-detection based on physical cores is
    # already sensible.
    "config/paper-global.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        chunk-system.io-threads = 4;
      };
    };

    "plugins/BlueMap/core.conf" = {
      format = pkgs.formats.json { };
      value = {
        accept-download = true;
        # Default 8100 collides with creative's BlueMap on this same
        # host -- ports.nix's bluemapHardcore entry forwards this same
        # 8101.
        webserver.port = 8101;
      };
    };

    # Two layers, both needed -- min-inhabited-time alone isn't enough:
    # once a chunk's surface has been visited it passes that check, but
    # the whole vertical column (including caves you never mined into)
    # still renders, and BlueMap's 3D viewer's free-flight camera can
    # fly straight through walls to see it. remove-caves-below-y set
    # absurdly high (10000) strips cave geometry from the render
    # entirely, everywhere, regardless of visited status -- there's
    # nothing there to fly into even with free-flight on, since the data
    # was never included in the first place. Map id defaults to the
    # world folder name -- "world" here, matching server.nix's
    # level-name.
    "plugins/BlueMap/maps/world.conf" = {
      format = pkgs.formats.json { };
      value = {
        # Required -- without this, BlueMap can't associate the map
        # entry with an actual world at all and disables itself
        # entirely ("no valid maps configured"), confirmed on first
        # boot 2026-08-10 (my original config only set the two options
        # below, missing this).
        world = "world";
        dimension = "minecraft:overworld";
        min-inhabited-time = 1;
        remove-caves-below-y = 10000;
      };
    };

    # `lodDistanceChunks` (NOT `lodStreamRadius` -- that key doesn't
    # exist in this plugin version at all; confirmed by reading the
    # actual generated config after first boot 2026-08-10, where an
    # earlier version of this file's wrong key silently did nothing and
    # the plugin ran at its own 512-chunk/8192-block default instead).
    # Nerfed to 64 chunks (1024 blocks) -- still double the maxed-out
    # 32-chunk simulation-distance (server.nix), so it extends visual
    # range meaningfully beyond what vanilla ever shows, without turning
    # it into a "see the whole map before you've earned it" tool. No
    # structure-specific filter exists in this plugin -- whatever falls
    # inside this radius (villages, temples, etc. included) streams as
    # real LOD data, real chunk gen, same seed.
    "plugins/VoxyServerSide/vss-server-config.json" = {
      format = pkgs.formats.json { };
      value = {
        lodDistanceChunks = 64;
      };
    };

    # Port 8091, not MCPanel's default 8090 -- filebrowser (self-hosted)
    # already owns 8090 on this host, confirmed as a real collision risk
    # on first boot 2026-08-10 (MCPanel was still binding 8090 despite
    # ports.nix's forward already being 8091, since only the port-forward
    # existed -- this file is what actually makes MCPanel itself listen
    # on the right port).
    #
    # Real auth credentials, not the "admin"/"admin" default the plugin
    # ships with -- that default plus its own hardcoded default
    # jwt-secret would be a live admin-console login sitting on
    # well-known credentials once this port is forwarded. jwt-secret
    # still generated fresh (never given, no reason to reuse the
    # plugin's own hardcoded default either). config/github/
    # replacements.nix has the matching redaction entry, same mechanism
    # as server.nix's RCON password.
    "plugins/MCPanel/config.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        panel.port = 8091;
        panel.host = "0.0.0.0";
        auth.username = "maxmustermann";
        auth.password = "changeme";
        auth.jwt-secret = "changeme";
        auth.token-hours = 24;
      };
    };
  };
}
