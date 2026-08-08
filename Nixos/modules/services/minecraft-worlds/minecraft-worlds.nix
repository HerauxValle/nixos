# &desc: "Minecraft world creation logic -- groups config.vars.minecraft.worlds entries by server, generates each server's extraStartPost script plus a Skript-based permadeath script for hardcore = true dimensions and LuckPerms gamemode-switch grants for gamemode = \"creative\" dimensions."

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
    + lib.optionalString (w.generatorSettings != null) " --generator-settings ${w.generatorSettings}"
    + lib.optionalString (w.seed != null) " --seed ${w.seed}";

  # One { dimName; createCmd; regenerate; gamemode; hardcore; } per
  # dimension this group actually wants -- the overworld always,
  # nether/end only if that group's flag is set. regenerate/gamemode/
  # hardcore are the same for every dimension in a group (whole-group
  # settings, not per-dimension).
  mkGroupCmds =
    name: w:
    let
      dims =
        [
          {
            dimName = name;
            createCmd = mkOverworldCmd name w;
          }
        ]
        ++ lib.optional w.nether {
          dimName = "${name}_nether";
          createCmd = "mv create ${name}_nether nether";
        }
        ++ lib.optional w.end {
          dimName = "${name}_the_end";
          createCmd = "mv create ${name}_the_end the_end";
        };
    in
    map (d: d // { inherit (w) regenerate gamemode hardcore; }) dims;

  mkDimScript =
    d:
    (
      if d.regenerate then
        ''
          send "mv delete ${d.dimName}"
          sleep 3
          send ${lib.escapeShellArg d.createCmd}
          sleep 3
        ''
      else
        ''
          [ -d ${lib.escapeShellArg d.dimName} ] || send ${lib.escapeShellArg d.createCmd}
          sleep 3
        ''
    )
    + lib.optionalString (d.gamemode != null) ''
      send ${lib.escapeShellArg "mv modify ${d.dimName} set gamemode ${d.gamemode}"}
      sleep 1
    '';

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
    serverName: dims:
    ''
      SOCK="/run/minecraft/${serverName}.sock"
      send() { ${pkgs.tmux}/bin/tmux -S "$SOCK" send-keys "$1" Enter; }
      sleep 20
    ''
    + lib.concatMapStringsSep "\n" mkDimScript dims;

  # Skript, not vanilla's real hardcore flag -- Multiverse-created worlds
  # can't have that (see world-type.nix's own comment on `hardcore` for
  # why). Bans the player on death in any dimension across every
  # hardcore = true group, for however many such worlds exist.
  mkHardcoreScript =
    hardcoreDimNames:
    let
      condition = lib.concatMapStringsSep " or " (n: ''world of player is "${n}"'') hardcoreDimNames;
    in
    ''
      on death of player:
      	if ${condition}:
      		kick player due to "&c&lPERMADEATH&r&c - you died in a hardcore world"
      		ban player due to "Hardcore permadeath"
    '';

  # Anyone in a gamemode = "creative" world gets the ability to actually
  # flip their own gamemode -- Multiverse's enforce-gamemode only forces
  # the *initial* switch on world-change, it doesn't grant the player any
  # lasting permission of their own. LuckPerms' per-world context
  # ("world=<name>") is what scopes this to exactly the creative worlds,
  # not server-wide. Two separate nodes needed: minecraft.command.gamemode
  # for the actual /gamemode text command, f3nperm.use for the F3+F4 GUI
  # shortcut specifically -- that one checks vanilla OP status directly,
  # bypassing Bukkit permissions entirely, unless F3NPerm (see hardcore.nix)
  # is installed to make it respect this node instead.
  mkGamemodePermCmds =
    dimName: ''
      send "lp group default permission set minecraft.command.gamemode true world=${dimName}"
      sleep 1
      send "lp group default permission set f3nperm.use true world=${dimName}"
      sleep 1
    '';

  dimsByServer = lib.mapAttrs (
    _: serverWorlds: lib.concatMap (e: mkGroupCmds e.name e.value) serverWorlds
  ) byServer;

  hardcoreDimsByServer = lib.mapAttrs (
    _: dims: map (d: d.dimName) (lib.filter (d: d.hardcore) dims)
  ) dimsByServer;

  creativeDimsByServer = lib.mapAttrs (
    _: dims: map (d: d.dimName) (lib.filter (d: d.gamemode == "creative") dims)
  ) dimsByServer;
in
{
  config = lib.mkIf (worlds != { }) {
    services.minecraft-servers.servers = lib.mapAttrs (
      serverName: dims:
      let
        hardcoreDims = hardcoreDimsByServer.${serverName};
        creativeDims = creativeDimsByServer.${serverName};
      in
      let
        extraSymlinks =
          lib.optionalAttrs (hardcoreDims != [ ]) {
            "plugins/Skript.jar" = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/xFNYAvMk/versions/9s2QlgIA/Skript-2.16.1.jar";
              hash = "sha256-g1ejSLJ82KLPdJmY5K0UvR3KMWACa9MELW0Xz7TJinA=";
            };
          }
          // lib.optionalAttrs (creativeDims != [ ]) {
            "plugins/LuckPerms.jar" = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/Vebnzrzj/versions/b0mk8uS6/LuckPerms-Bukkit-5.5.71.jar";
              hash = "sha256-Sc7LZvof0ioTMDmkkOnB5QlaI4581m650qFv5siXVQ0=";
            };
          };

        extraFiles = lib.optionalAttrs (hardcoreDims != [ ]) {
          "plugins/Skript/scripts/hardcore-permadeath.sk" = pkgs.writeText "hardcore-permadeath.sk" (
            mkHardcoreScript hardcoreDims
          );
        };
      in
      {
        extraStartPost =
          mkServerScript serverName dims
          + lib.concatMapStringsSep "\n" mkGamemodePermCmds creativeDims;
      }
      // lib.optionalAttrs (extraSymlinks != { }) { symlinks = extraSymlinks; }
      // lib.optionalAttrs (extraFiles != { }) { files = extraFiles; }
    ) dimsByServer;
  };
}
