# &desc: "Minecraft world creation schema -- config.vars.minecraft.worlds entries generate idempotent /mv create console commands via each target server's extraStartPost, plus config.vars.minecraft.ops for server-wide operator status."

{ lib, ... }:

{
  imports = [ ./minecraft-worlds.nix ];

  options.vars.minecraft.dataDir = lib.mkOption {
    type = lib.types.str;
    description = ''
      Single source of truth for services.minecraft-servers.dataDir --
      set once here and wired into that option by
      config/software/programs/minecraft/settings.nix, so anything
      needing to reference or compute a path relative to it has one
      place to read it from instead of a hardcoded duplicate.
    '';
  };

  options.vars.minecraft.premiumAddons = lib.mkOption {
    type = lib.types.str;
    description = ''
      Where paid/Patreon plugin and mod jars are kept on disk, outside
      the Nix store (not redistributable). Set once in
      config/software/programs/minecraft/settings.nix; servers/creative/plugins.nix
      symlinks straight into here.
    '';
  };

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

  options.vars.minecraft.ops = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
    description = ''
      Server operators, keyed by services.minecraft-servers.servers.<name>
      (e.g. config.vars.minecraft.ops.hardcore = [ "HerauxValle" ]).
      There's no native per-world equivalent -- OP is a vanilla concept
      tied to the whole server (ops.json), not any single world/dimension,
      so unlike `worlds` above this can't be scoped to one world even if
      you wanted it to be. Generates an idempotent /op <name> console
      command per player, appended to that server's extraStartPost.
    '';
  };

  options.vars.minecraft.servers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          startIn = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Where a player lands on their very first-ever join, and
              never again after that. "<world>" or "<world> x y z" (space
              separated, exact coordinates within that world). null/unset
              means Multiverse's own default (server.properties'
              spawn point) -- not "last location", since there's no last
              location yet on a first join.
            '';
          };
          loginIn = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Where a player lands on every join after their first,
              forever. Same "<world>" or "<world> x y z" format as
              startIn. null/unset means the player's last logout
              location, i.e. normal vanilla behavior.
            '';
          };
          autostart = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              false (default) -- the server is built/enabled but does
              NOT start on boot; you have to start it yourself
              (systemctl start minecraft-server-<name>). true --
              WantedBy=multi-user.target, same as leaving this unset
              used to mean before this option existed (the base
              services.minecraft-servers module sets that automatically
              whenever a server's `enable = true`; this option
              overrides it per-server). Deliberately opt-in, not
              opt-out, since a server auto-starting is a much bigger
              surprise than one you have to remember to start.
            '';
          };
        };
      }
    );
    default = { };
    description = ''
      Per-server join-spawn behavior + autostart, keyed by
      services.minecraft-servers.servers.<name> (e.g.
      config.vars.minecraft.servers.creative.startIn = "hub"). startIn/
      loginIn are backed by Multiverse-Core's first-spawn-override/
      join-destination -- see minecraft-worlds.nix's mkSpawnConfig, also
      disables Multiverse's safe-location veto entirely (search radius
      0) whenever either is set, since a void/flat world spawn point
      otherwise fails with "UNSAFE_LOCATION" and silently falls back to
      last location. autostart is unrelated to Multiverse -- see its own
      description above.
    '';
  };
}
