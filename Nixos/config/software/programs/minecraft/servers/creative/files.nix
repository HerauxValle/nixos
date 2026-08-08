# &desc: "Creative server's config-file overrides -- BlueMap accept-download, Multiverse join-destination/confirm-mode, server-icon, and the hub/creative/world command aliases."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.creative = {
    files."plugins/BlueMap/core.conf" = {
      format = pkgs.formats.json { };
      value = {
        accept-download = true;
      };
    };

    # Shown in the client's multiplayer server list -- must be exactly 64x64.
    files."server-icon.png" = ../../icons/hardcore.png;

    # The spawn.join-destination keys here come from worlds.nix's
    # defaultSpawn = true (see modules/services/minecraft-worlds), not
    # this file -- Nix merges both into the same config.yml.
    files."plugins/Multiverse-Core/config.yml".value = {
      # "disable_console" (not "disable") -- players still get the usual
      # /mv confirm prompt for their own destructive commands, only
      # minecraft-worlds.nix's extraStartPost script (running over the
      # server console, not as a player) skips it, needed for
      # regenerate = true worlds' /mv delete to run unattended.
      command.confirm-mode = "disable_console";
    };

    # /hub as a manual way back, on top of the automatic every-join spawn
    # above -- aliases to Multiverse-Core's own self-teleport command.
    # /creative is shorthand for /gamemode creative -- still gated by the
    # same per-world LuckPerms grant as the underlying command (see
    # modules/services/minecraft-worlds/minecraft-worlds.nix's
    # mkGamemodePermCmds), aliasing doesn't bypass that. /world <name> is
    # /mvtp $1 -- <name> is whatever key you used under worlds.nix (e.g.
    # /world redstone, /world hub).
    #
    # --unsafe skips Multiverse's safe-location scan (hub's void floor and
    # any custom flat world can otherwise fail with "location deemed
    # unsafe!", confirmed 2026-08-09) -- --silent drops its own "Teleported
    # you to X" chat message on top of that.
    files."commands.yml".value = {
      aliases = {
        hub = [ "mvtp hub --unsafe --silent" ];
        creative = [ "gamemode creative" ];
        world = [ "mvtp $$1 --unsafe --silent" ]; # $$ instead of $ -- fails cleanly on /world with no argument
      };
    };
  };
}
