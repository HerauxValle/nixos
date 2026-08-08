# &desc: "Minecraft world creation logic -- groups config.vars.minecraft.worlds entries by server, generates each server's extraStartPost script (overworld plus its own nether/end)."

{ config, lib, pkgs, ... }:

let
  worlds = config.vars.minecraft.worlds;

  byServer = lib.groupBy (e: e.value.server) (
    lib.mapAttrsToList (name: value: { inherit name value; }) worlds
  );

  mkOverworldCmd =
    name: w:
    "mv create ${name} normal"
    + lib.optionalString (w.worldType != null) " --world-type ${w.worldType}"
    + lib.optionalString (w.generatorSettings != null) " --generator-settings ${w.generatorSettings}";

  # One { name; cmd; } per dimension this group actually wants -- the
  # overworld always, nether/end only if that group's flag is set.
  mkGroupCmds =
    name: w:
    [ { inherit name; cmd = mkOverworldCmd name w; } ]
    ++ lib.optional w.nether {
      name = "${name}_nether";
      cmd = "mv create ${name}_nether nether";
    }
    ++ lib.optional w.end {
      name = "${name}_the_end";
      cmd = "mv create ${name}_the_end the_end";
    };

  # A fixed sleep instead of polling the log for "Done (" -- tried that
  # first, but latest.log's rotation timing (old file -> dated .log.gz,
  # fresh empty file) races against ExecStartPost's own start (fires the
  # instant the tmux-wrapped start script *returns*, near-instant under
  # Type=forking, well before Paper/Multiverse actually finish booting
  # inside that session). Capturing a line-count offset before rotation
  # lands means the offset never gets reached again, so the poll just
  # burns its full timeout every time. Not worth chasing further: Paper
  # boots in ~8s in practice and Multiverse's own create command is
  # idempotent (harmlessly logs "already exists" if this fires early on
  # a world that's already there), so a generous flat sleep is simpler
  # and just as correct.
  mkServerScript =
    serverName: serverWorlds:
    ''
      SOCK="/run/minecraft/${serverName}.sock"
      send() { ${pkgs.tmux}/bin/tmux -S "$SOCK" send-keys "$1" Enter; }
      sleep 20
    ''
    + lib.concatMapStringsSep "\n" (
      d: ''
        [ -d ${lib.escapeShellArg d.name} ] || send ${lib.escapeShellArg d.cmd}
        sleep 3
      ''
    ) (lib.concatMap (e: mkGroupCmds e.name e.value) serverWorlds);
in
{
  config = lib.mkIf (worlds != { }) {
    services.minecraft-servers.servers = lib.mapAttrs (serverName: serverWorlds: {
      extraStartPost = mkServerScript serverName serverWorlds;
    }) byServer;
  };
}
