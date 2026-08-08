# &desc: "Minecraft world creation schema -- config.vars.minecraft.worlds entries generate idempotent /mv create console commands via each target server's extraStartPost."

{ lib, ... }:

{
  imports = [ ./minecraft-worlds.nix ];

  options.vars.minecraft.worlds = lib.mkOption {
    type = lib.types.attrsOf (import ./lib/world-type.nix { inherit lib; });
    default = { };
    description = ''
      Multiverse-managed worlds to create declaratively, keyed by the
      world's own name (e.g. config.vars.minecraft.worlds.creative). Each
      entry's `server` field points at the
      services.minecraft-servers.servers.<name> it belongs to -- one
      /mv create console command per entry gets appended to that server's
      extraStartPost, guarded by checking the world's folder on disk
      first (a no-op after the first successful run -- world data
      persists in dataDir like any other save; Multiverse's own
      duplicate-create check backs this up too). See ./lib/world-type.nix
      for the field list.
    '';
  };
}
