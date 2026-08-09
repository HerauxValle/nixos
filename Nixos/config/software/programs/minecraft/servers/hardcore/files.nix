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
        min-inhabited-time = 1;
        remove-caves-below-y = 10000;
      };
    };

    # lodStreamRadius nerfed way down from the plugin's 256-chunk
    # (4096-block) default -- 64 chunks (1024 blocks) is still double
    # the maxed-out 32-chunk simulation-distance (server.nix), so it
    # extends visual range meaningfully beyond what vanilla ever shows,
    # without turning it into a "see the whole map before you've earned
    # it" tool. No structure-specific filter exists in this plugin --
    # whatever falls inside this radius (villages, temples, etc.
    # included) streams as real LOD data, real chunk gen, same seed.
    #
    # CAVEAT: the plugin also exposes a client-side "personal LOD stream
    # radius" preference (0 = use this server default) -- I found no
    # confirmation this server-side value acts as a hard ceiling
    # independent of that client override, so treat this as the
    # *default*, not a guaranteed cap, until verified against the
    # actual running plugin.
    "plugins/VoxyServerSide/vss-server-config.json" = {
      format = pkgs.formats.json { };
      value = {
        lodStreamRadius = 64;
      };
    };
  };
}
