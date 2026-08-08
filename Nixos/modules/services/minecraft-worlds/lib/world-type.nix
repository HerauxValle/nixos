# &desc: "Per-world submodule for config.vars.minecraft.worlds -- server binding, /mv create's environment/world-type/generator-settings flags."

{ lib }:

lib.types.submodule {
  options = {
    server = lib.mkOption {
      type = lib.types.str;
      description = "services.minecraft-servers.servers.<name> this world belongs to.";
    };

    environment = lib.mkOption {
      type = lib.types.enum [
        "normal"
        "nether"
        "the_end"
      ];
      description = "Passed straight through to /mv create's <environment> positional argument.";
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
      description = "null -- omit --world-type entirely (vanilla terrain). Otherwise passed as --world-type.";
    };

    generatorSettings = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Raw JSON string passed to /mv create's --generator-settings flag,
        e.g. '{"layers":[{"block":"minecraft:white_stained_glass","height":1}],"biome":"minecraft:plains"}'.
        null omits the flag entirely.
      '';
    };
  };
}
