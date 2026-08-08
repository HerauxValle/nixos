# &desc: "Creative server's world declarations -- hub (void lobby), redstone/building (kept-progress superflat builds), temp (disposable normal-terrain testing ground)."

{ ... }:

{
  # Declarative world creation -- schema + logic in
  # modules/services/minecraft-worlds/, generates each group's /mv create
  # console command(s) into services.minecraft-servers.servers.<server>.
  # extraStartPost, one entry per world-group (not per dimension) --
  # nether/end are just flags on the group they belong to.
  vars.minecraft.worlds = {
    hub = {
      server = "creative";
      worldType = "flat";
      generatorSettings = ''{"layers":[],"biome":"the_void"}'';
      seed = "0";
      gamemode = "creative"; # so you can fly instead of falling into the void
      regenerate = false;
      # No nether/end -- overworld-only lobby.
    };

    redstone = {
      server = "creative";
      worldType = "flat";
      generatorSettings = ''{"layers":[{"block":"minecraft:white_stained_glass","height":1}],"biome":"minecraft:plains"}'';
      seed = "0";
      nether = true;
      end = true;
      gamemode = "creative";
      regenerate = false; # a build world -- keep progress
    };

    building = {
      server = "creative";
      worldType = "flat";
      generatorSettings = ''{"layers":[{"block":"minecraft:bedrock","height":1},{"block":"minecraft:dirt","height":6},{"block":"minecraft:grass_block","height":1}],"biome":"minecraft:plains"}'';
      seed = "0";
      nether = true;
      end = true;
      gamemode = "creative";
      regenerate = false; # a second build world -- keep progress
    };

    temp = {
      server = "creative";
      # worldType left null -- normal vanilla terrain, not flat.
      seed = "1";
      nether = true;
      end = true;
      gamemode = "creative";
      regenerate = true; # disposable/testing ground -- wiped + recreated on every boot
    };
  };
}
