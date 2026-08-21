# &desc: "Per-world-group submodule for config.vars.minecraft.worlds -- one overworld plus which of its own nether/end to also create."

{ lib }:

lib.types.submodule {
  options = {
    server = lib.mkOption {
      type = lib.types.str;
      description = "services.minecraft-servers.servers.<name> this world group belongs to.";
    };

    multiverse = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        true (default) -- this group is Multiverse-managed: worldType,
        generatorSettings, nether, end, gamemode, and this schema's
        simulated `hardcore` all apply, via /mv create console commands
        in the target server's extraStartPost (existing behavior,
        unchanged).

        false -- no Multiverse plugin on the target server. This becomes
        that server's one real default world instead of an
        additional Multiverse-created one: worldType, generatorSettings,
        nether, end, gamemode, and `hardcore` are all no-ops (a vanilla
        server has exactly one world, and vanilla's real hardcore flag
        -- see serverProperties.hardcore in the server's own config --
        already covers permadeath for it directly, not this schema's
        Skript-simulated version). Only `seed` (-> serverProperties.
        level-seed) and `regenerate` (-> unconditionally archives the
        server's actual level-name folder into trash/ on every start,
        letting vanilla rebootstrap fresh against that seed) do anything
        in this mode.
      '';
    };

    worldType = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "flat"
          "large_biomes"
          "amplified"
        ]
      );
      default = null;
      description = ''
        Applies to this group's overworld only -- null omits --world-type
        entirely (vanilla terrain). Otherwise passed as --world-type to
        /mv create.
      '';
    };

    generatorSettings = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Applies to this group's overworld only -- raw JSON string passed
        to /mv create's --generator-settings flag, e.g.
        '{"layers":[{"block":"minecraft:white_stained_glass","height":1}],"biome":"minecraft:plains"}'.
        null omits the flag entirely.
      '';
    };

    nether = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also create <name>_nether (vanilla nether terrain). Naming
        matches Multiverse-NetherPortals' own auto-link convention (see
        modules/system/port-forwarding, same idea), so a portal built in
        this group's overworld always lands in its own nether, never
        another group's.
      '';
    };

    end = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also create <name>_the_end (vanilla end terrain). Same naming
        convention as `nether` above.
      '';
    };

    seed = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Applies to this group's overworld only -- passed to /mv create's
        --seed flag. null omits the flag (random seed).
      '';
    };

    gamemode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "survival"
          "creative"
          "adventure"
          "spectator"
        ]
      );
      default = null;
      description = ''
        Applies to every dimension in this group (overworld + nether/end
        if enabled) via /mv modify set gamemode -- combined with
        Multiverse-Core's config.yml enforce-gamemode/enforce-flight
        (both true by default), this is what actually grants/denies
        creative-mode access per world, no separate permissions plugin
        needed. null leaves Multiverse's own default (survival) alone.
      '';
    };

    regenerate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        false (default) -- normal idempotent behavior, only created once,
        left alone forever after (guarded by checking the world's folder
        on disk). true -- unconditionally deletes and recreates every
        dimension in this group on EVERY server start, forever, until
        set back to false. Only meant for disposable/testing worlds --
        never leave this true on a world you actually want to keep
        progress in.
      '';
    };

    hardcore = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Simulated permadeath for every dimension in this group -- NOT
        vanilla's real hardcore world flag (Multiverse-created worlds
        can't have that; it only ever applies to the one
        vanilla-bootstrapped default world per server, see
        serverProperties.hardcore in the server's own config). true
        installs Skript (if not already present from another entry) and
        generates a small script that bans the player on death in any
        dimension across every hardcore = true group -- same practical
        consequence, but works for any number of worlds, not just one.
      '';
    };
  };
}
