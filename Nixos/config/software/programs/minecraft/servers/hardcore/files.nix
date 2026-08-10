# &desc: "Hardcore server's config-file overrides -- server-icon, BlueMap's accept-download + fog-of-war (min-inhabited-time) + full cave removal (remove-caves-below-y), paper-global.yml's chunk-system IO threads, paper-world-defaults.yml + spigot.yml's pure-performance/bug-fix tuning (see inline comments)."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore.files = {
    "server-icon.png" = ../../icons/hardcore.png;

    # Commented out -- ClearLaggEnhanced itself commented out in
    # plugins.nix (see its comment for why).
    # "plugins/ClearLaggEnhanced/config.yml" = {
    #   format = pkgs.formats.yaml { };
    #   value = {
    #     database = {
    #       enabled = true;
    #       type = "sqlite";
    #       file = "clearlagg.db";
    #       mysql = {
    #         host = "localhost";
    #         port = 3306;
    #         database = "clearlagg";
    #         username = "root";
    #         password = "password";
    #         ssl-mode = "PREFERRED";
    #         properties = { };
    #       };
    #       pool = {
    #         maximum-pool-size = 10;
    #         minimum-idle = 2;
    #         connection-timeout-ms = 10000;
    #         idle-timeout-ms = 600000;
    #         max-lifetime-ms = 1800000;
    #         keepalive-time-ms = 0;
    #         validation-timeout-ms = 5000;
    #       };
    #     };
    #     modules = {
    #       entity-clearing = false;
    #       mob-limiter = true;
    #       spawner-limiter = true;
    #       misc-entity-limiter = true;
    #       chunk-finder = true;
    #       performance = true;
    #       packet-limiter = false;
    #       afk = false;
    #       wildstacker = false;
    #       rosestacker = false;
    #       modernshowcase = false;
    #       griefprevention3d = false;
    #     };
    #   };
    # };

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

    # From the "6 config files performance" video review -- only the
    # entries confirmed as pure performance/bug-fixes with zero mechanic
    # change made the cut (see plugins.nix's top &desc / conversation for
    # what was rejected and why, including two whole config files --
    # pufferfish.yml, purpur.yml -- that don't even apply since this is
    # plain Paper, not those forks).
    "config/paper-world-defaults.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        chunks = {
          delay-chunk-unloads-by = "10s";
          max-auto-save-chunks-per-tick = 8;
          # Bug-prevention, not a mechanic change -- stops an unfair
          # glitch-fall through the world during chunk-load lag.
          prevent-moving-into-unloaded-chunks = true;
        };
        # Paper's own docs confirm this produces identical explosion
        # outcomes, just computed faster -- not a behavior change.
        environment.optimize-explosions = true;
        # Closes a real exploit (climbing entities bypassing the entity-
        # cramming damage rule) -- a fix, not a nerf, same spirit as the
        # Loyal Tridents void-throw fix considered earlier.
        collisions.fix-climbing-bypassing-cramming-rule = true;
      };
    };

    # merge-radius only affects how close nearby dropped items/XP orbs
    # need to be before they visually merge into one stacked entity --
    # doesn't change what you actually collect, just entity count/visual
    # clutter.
    #
    # world-settings.default.merge-radius, NOT the top-level merge-radius
    # key -- confirmed by reading the actual generated spigot.yml after
    # boot 2026-08-10: the top-level key I originally set sits there
    # unused (still showed vanilla's 0.5/-1.0 under world-settings.default
    # even with the top-level key correctly applied), because that's the
    # real, actually-read path; the top-level one is a vestigial/legacy
    # key Spigot keeps around but doesn't act on.
    "spigot.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        world-settings.default.merge-radius = {
          item = 3.5;
          exp = 4.5;
        };
      };
    };

    # config.yml's own top-level "profiles" list is NOT what's actually
    # read -- confirmed by a raw server-list ping after boot 2026-08-10
    # still returning the plugin's own shipped example text ("Line A" /
    # "Line B"), same vestigial-key trap as spigot.yml's merge-radius
    # earlier. The real, per-server file the plugin actually reads is
    # profiles/default.yml (auto-generated on first boot with that exact
    # example content baked in, and NOT covered by nix-minecraft's file
    # management unless explicitly listed here, so it just persisted).
    # This sets the flat top-level "motd" key in that file directly and
    # leaves its own "profiles" list empty -- an empty/absent nested
    # profiles list falls through to this flat motd (confirmed via the
    # file's own inline doc comment: "When not present or empty
    # (profiles: []), no profiles will be used and global options from
    # the file will be used instead").
    "plugins/AdvancedServerList/profiles/default.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        priority = 0;
        condition = "";
        profiles = [ ];
        motd = [
          "<gold><bold>Hardcore</bold></gold>"
          "<gray>One life. No second chances.</gray>"
        ];
      };
    };

    "plugins/BlueMap/core.conf" = {
      format = pkgs.formats.json { };
      value = {
        accept-download = true;
      };
    };

    # The actual webserver port lives in a SEPARATE webserver.conf file,
    # not core.conf's "webserver.port" (that key doesn't do anything --
    # confirmed on first boot 2026-08-10, BlueMap kept binding 8100
    # despite core.conf having webserver.port: 8101 set correctly).
    # Default 8100 collides with creative's BlueMap on this same host --
    # ports.nix's bluemapHardcore entry forwards this same 8101.
    "plugins/BlueMap/webserver.conf" = {
      format = pkgs.formats.json { };
      value = {
        port = 8101;
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
    # config.yml's own "auth" block turned out to be a dead/legacy path
    # -- confirmed by testing the login API directly (2026-08-10): it
    # authenticates fine but grants a "custom" role with EVERY
    # permission false (console/dashboard/management all denied), which
    # is why login looked like it was failing. jwt-secret here is still
    # real (used for signing regardless of which login path is active).
    "plugins/MCPanel/config.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        panel.port = 8091;
        panel.host = "0.0.0.0";
        auth.jwt-secret = "changeme";
        auth.token-hours = 24;
      };
    };

    # The REAL account system -- plugin generates its own users.json on
    # first boot with a hardcoded "admin"/"admin" full-permission
    # account (confirmed by testing that exact login directly, it works
    # and returns role: admin with every permission true). That's the
    # actual live security hole, worse than config.yml's dead auth
    # block ever was. This replaces it outright with a real account --
    # nix-minecraft's file management overwrites this file every boot,
    # so the plugin's own auto-generated "admin" entry never persists.
    # passwordHash is a real bcrypt hash (cost 10) of the same password
    # used elsewhere, computed and verified locally with `python3
    # -c "import bcrypt; ..."` (bcrypt.checkpw confirmed a match) --
    # never sent anywhere. config/github/replacements.nix has the
    # matching redaction entries for both this and the password itself
    # documented in this file's history.
    "plugins/MCPanel/users.json" = {
      format = pkgs.formats.json { };
      value = {
        herauxvalle = {
          passwordHash = "changeme";
          role = "admin";
          permissions = {
            console = true;
            management_files = true;
            management = true;
            players = true;
            management_plugins = true;
            players_interact = true;
            dashboard_console = true;
            management_users = true;
            dashboard = true;
            management_settings = true;
          };
        };
      };
    };

    # /vd and /sd -- short aliases to the two ViewDistanceTweaks (plugins.nix)
    # commands you actually use. Native Paper feature, no extra plugin
    # needed (same mechanism creative/files.nix uses for /hub, /creative,
    # /world).
    # Tailored for hardcore's context -- same gold/gray "one life, no
    # second chances" palette as AdvancedServerList's MOTD (this file's
    # own profiles/default.yml, below), a dark-red->gold gradient title
    # for the ominous permadeath feel, no rank/group sorting since
    # ops.nix stays permanently empty (alphabetical is the only sorting
    # that makes sense with everyone in the same "default" group). Only
    # the keys that matter are set here; TAB auto-patches in its own
    # defaults for everything else on first load (confirmed pattern
    # elsewhere in this repo -- see ViewDistanceTweaks/config.yml's own
    # comment below for the same caveat). MiniMessage gradients need
    # components.minimessage-support (TAB's own shipped default: true,
    # left untouched here). Verify against the real generated
    # plugins/TAB/config.yml after first boot.
    "plugins/TAB/config.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        header-footer = {
          enabled = true;
          designs.default = {
            header = [
              "<dark_gray><strikethrough>                                        </strikethrough></dark_gray>"
              "<gradient:#8B0000:#FFD700:#8B0000><bold>☠ HARDCORE ☠</bold></gradient>"
              "<gray><italic>One life. No second chances.</italic></gray>"
              ""
            ];
            footer = [
              ""
              "<gray>Ping <white>%ping%ms</white>  <dark_gray>|</dark_gray>  <gray>Mem <white>%memory-used%</white>/<white>%memory-max%</white>MB</gray>"
              "<gold>%time%</gold>"
              "<dark_gray><strikethrough>                                        </strikethrough></dark_gray>"
            ];
          };
        };
        # No rank hierarchy here -- alphabetical is the only sorting
        # that makes sense with ops.nix permanently empty.
        scoreboard-teams.sorting-types = [ "PLACEHOLDER_A_TO_Z:%player%" ];
        playerlist-objective = {
          enabled = true;
          value = "%ping%";
          fancy-value = "<gold>%ping%ms</gold>";
        };
        # Not clustered with anything else -- avoids stray
        # RedisBungee-lookup warnings on boot.
        proxy-support.enabled = false;
        # REQUIRED -- without this, TAB's own config-updater treats the
        # file as an old/unversioned config on load and rewrites
        # designs.default's header/footer back to empty arrays,
        # silently discarding everything set above (confirmed the hard
        # way 2026-08-11: first boot produced header: [] / footer: []
        # despite this file having real content). 7 is this TAB
        # version's (6.1.2) own current config-version, confirmed from
        # its shipped default config.yml.
        config-version = 7;
      };
    };

    "commands.yml".value = {
      aliases = {
        vd = [ "vdt viewdistance $1" ];
        sd = [ "vdt simulationdistance $1" ];
        # clearitems = [ "lagg clear" ]; -- ClearLaggEnhanced commented
        # out (plugins.nix), this would no-op.
      };
    };

    # IMPORTANT: this build ("ViewDistanceTweaks - LucasTHCR Edition", a
    # fork of the original plugin) ships with enabled: true and a live
    # mixed-mode auto-adjuster OUT OF THE BOX -- confirmed the hard way
    # 2026-08-10 when /vdt status showed it had already drifted the
    # world off server.nix's static 8/5 (to 9/6) despite this file
    # having no entry at all yet. The original plugin defaults to off;
    # this fork does not. enabled: false here turns that off for real,
    # leaving server.nix's static 8/5 as the only thing setting
    # view/simulation-distance unless you run /vd or /sd (or /vdt
    # enable) yourself. Every other key left at the fork's own
    # shipped default (confirmed against the real generated config.yml
    # after first boot) -- only reachable at all once you flip this
    # back to true.
    "plugins/ViewDistanceTweaks/config.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        version = 1;
        enabled = false;
        adjustment-mode = "mixed";
        start-delay = 2400;
        ticks-per-check = 600;
        passed-checks-for-increase = 10;
        passed-checks-for-decrease = 1;
        log-changes = true;
        announce-changes-in-chat = false;
        proactive-mode-settings = {
          global-ticking-chunk-count-target = 5780;
          global-non-ticking-chunk-count-target = 6720;
          empty-world-target = "min";
        };
        reactive-mode-settings = {
          increase-mspt-threshold = 40.0;
          decrease-mspt-threshold = 47.0;
          prioritize-simulation-distance = false;
          max-increase-step = 1;
          max-decrease-step = 1;
          revert-increase-if-overloaded = true;
        };
        world-settings.default = {
          simulation-distance = {
            exclude = false;
            min-simulation-distance = 4;
            max-simulation-distance = 5;
          };
          view-distance = {
            exclude = false;
            min-view-distance = 6;
            max-view-distance = 8;
          };
          chunk-weight = 1.0;
        };
      };
    };
  };
}
