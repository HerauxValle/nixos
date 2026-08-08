# &desc: "Per-world-group submodule for config.vars.minecraft.worlds -- one overworld plus which of its own nether/end to also create."

{ lib }:

lib.types.submodule {
  options = {
    server = lib.mkOption {
      type = lib.types.str;
      description = "services.minecraft-servers.servers.<name> this world group belongs to.";
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
  };
}
