# &desc: "Minecraft world creation logic -- groups config.vars.minecraft.worlds entries by server, generates each server's extraStartPre (trash dimensions dropped from the declaration) and extraStartPost (world creation, gamemode/perm grants) scripts plus a Skript-based permadeath script for hardcore = true dimensions and Multiverse spawn config from config.vars.minecraft.servers.*.startIn/loginIn."

{ config, lib, pkgs, ... }:

let
  worlds = config.vars.minecraft.worlds;
  ops = config.vars.minecraft.ops;
  spawnCfg = config.vars.minecraft.servers;

  allWorldEntries = lib.mapAttrsToList (name: value: { inherit name value; }) worlds;

  # multiverse=false entries (world-type.nix) never touch mkGroupCmds/
  # mkDimScript/mkServerScript below -- byServer only ever sees
  # Multiverse-managed groups, so that whole pipeline (and every existing
  # creative/ world) is completely unchanged by their existence.
  byServer = lib.groupBy (e: e.value.server) (lib.filter (e: e.value.multiverse) allWorldEntries);

  # At most one multiverse=false entry per server -- a vanilla server has
  # exactly one default world, so more than one declared for the same
  # `server` is a config mistake, caught here instead of silently
  # picking one.
  nonMvByServer = lib.groupBy (e: e.value.server) (lib.filter (e: !e.value.multiverse) allWorldEntries);
  nonMvByServerChecked = lib.mapAttrs (
    serverName: entries:
    assert lib.assertMsg (lib.length entries <= 1)
      "vars.minecraft.worlds: server '${serverName}' has ${toString (lib.length entries)} multiverse=false entries -- a vanilla server can only have one default world, only one is allowed.";
    lib.head entries
  ) nonMvByServer;

  # Archives the server's *actual* level-name folder (read from its own
  # serverProperties, not this entry's own attr-set key -- the two are
  # unrelated identifiers) into trash/ unconditionally on every start.
  # Vanilla rebootstraps a fresh world against serverProperties.level-seed
  # (set below) the moment it finds that folder gone. Same trash-not-
  # delete convention as mkTrashScript.
  mkRegenScript =
    levelName: ''
      mkdir -p trash
      ts=$(date +%s)
      for d in ${lib.escapeShellArg levelName} ${lib.escapeShellArg "${levelName}_nether"} ${lib.escapeShellArg "${levelName}_the_end"}; do
        [ -d "$d" ] && mv "$d" "trash/''${ts}-$d"
      done
      true
    '';

  # OP/spawn are server-wide, not tied to any world -- a server can have
  # ops/startIn/loginIn declared with no worlds entries at all (or vice
  # versa), so this is every server name mentioned by any of the four,
  # not just dimsByServer's keys.
  allServerNames = lib.unique (
    (lib.attrNames byServer)
    ++ (lib.attrNames ops)
    ++ (lib.attrNames spawnCfg)
    ++ (lib.attrNames nonMvByServerChecked)
  );

  # "hub" -> "hub" (plain world-name destination). "hub 0 65 0" ->
  # "e:hub:0,65,0" (Multiverse's own EXACT destination-type syntax, same
  # one /mvtp accepts). Exactly a name plus 0 or 3 extra tokens is valid;
  # anything else is a config mistake best caught at eval time.
  parseDestination =
    str:
    let
      tokens = lib.filter (t: t != "") (lib.splitString " " str);
      name = lib.head tokens;
      coords = lib.tail tokens;
    in
    assert lib.assertMsg (coords == [ ] || lib.length coords == 3)
      "vars.minecraft.servers.*.startIn/loginIn: \"${str}\" must be \"<world>\" or \"<world> x y z\"";
    if coords == [ ] then name else "e:${name}:${lib.concatStringsSep "," coords}";

  mkOpsCmds =
    serverName: ''
      ${lib.concatMapStringsSep "\n" (n: ''
        send "op ${n}"
        sleep 1
      '') (ops.${serverName} or [ ])}
    '';

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
      # Paper boots in ~20-22s in practice -- 20s left ~0 margin and the
      # very first /mv create command raced Multiverse's command-context
      # setup (CommandSourceStack.getLevel() NPE, confirmed in the wild
      # 2026-08-08 on a fresh multi-world boot). 40s gives real headroom.
      sleep 40
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
  # flip their own gamemode via the /gamemode command -- Multiverse's
  # enforce-gamemode only forces the *initial* switch on world-change, it
  # doesn't grant the player any lasting permission of their own.
  # LuckPerms' per-world context ("world=<name>") is what scopes this to
  # exactly the creative worlds, not server-wide.
  #
  # F3+F4's GUI shortcut is NOT covered by this -- it checks vanilla OP
  # status directly, bypassing Bukkit's permission system entirely, and
  # no plugin fills that gap on this MC version (tried F3NPerm, its NMS
  # reflection provider doesn't recognize 26.1.2; documented "won't fix"
  # in Paper's own issue tracker #4986/#13489 besides). Use the text
  # command instead.
  mkGamemodePermCmds =
    dimName: ''
      send "lp group default permission set minecraft.command.gamemode true world=${dimName}"
      sleep 1
    '';

  # /hub and /world <name> (see hardcore.nix's commands.yml) are both
  # aliases for Multiverse-Core's own self-teleport command (/mvtp) --
  # config.yml's use-finer-teleport-permissions = true (Multiverse's own
  # default) means that needs a specific permission node per destination
  # type, not the older blanket "can teleport at all" node. Granted
  # server-wide (no per-world context, unlike the gamemode grants above)
  # since world-travel is meant to work from anywhere, not just certain
  # worlds.
  mkTeleportPermCmd = ''
    send "lp group default permission set multiverse.teleport.self.w.* true"
    sleep 1
  '';

  dimsByServer = lib.genAttrs allServerNames (
    name: lib.concatMap (e: mkGroupCmds e.name e.value) (byServer.${name} or [ ])
  );

  # Dimensions we created (per manifest of a previous run) that are no
  # longer declared get moved aside instead of deleted -- runs in
  # extraStartPre, before Multiverse/Paper touch the world folders.
  # Foreign/unmanaged directories (e.g. vanilla's own bootstrap
  # level-name world, if that name is never declared here) are never
  # in the manifest, so they're never touched by this.
  mkTrashScript =
    dimNames:
    let
      declared = lib.concatStringsSep " " dimNames;
      # Known at eval time -- write it verbatim, no runtime jq needed for
      # the write side (only the read side, comparing a previous run's
      # manifest, needs jq).
      manifestJson = builtins.toJSON dimNames;
    in
    ''
      MANIFEST=".managed-worlds.json"
      DECLARED=${lib.escapeShellArg declared}
      mkdir -p trash
      if [ -f "$MANIFEST" ]; then
        for prev in $(${pkgs.jq}/bin/jq -r '.[]' "$MANIFEST"); do
          case " $DECLARED " in
            *" $prev "*) ;;
            *) [ -d "$prev" ] && mv "$prev" "trash/$(date +%s)-$prev" ;;
          esac
        done
      fi
      cat > "$MANIFEST" <<'MANIFEST_EOF'
      ${manifestJson}
      MANIFEST_EOF
    '';

  hardcoreDimsByServer = lib.mapAttrs (
    _: dims: map (d: d.dimName) (lib.filter (d: d.hardcore) dims)
  ) dimsByServer;

  creativeDimsByServer = lib.mapAttrs (
    _: dims: map (d: d.dimName) (lib.filter (d: d.gamemode == "creative") dims)
  ) dimsByServer;
in
{
  config = lib.mkIf (worlds != { } || ops != { } || spawnCfg != { }) {
    services.minecraft-servers.servers = lib.mapAttrs (
      serverName: dims:
      let
        hardcoreDims = hardcoreDimsByServer.${serverName};
        creativeDims = creativeDimsByServer.${serverName};
        spawn = spawnCfg.${serverName} or {
          startIn = null;
          loginIn = null;
          autostart = false;
        };
        # The multiverse=false entry for this server, if any -- world-
        # type.nix guarantees at most one (nonMvByServerChecked's own
        # assert). null means this server has no such entry, same as
        # every server before this feature existed.
        nonMv = nonMvByServerChecked.${serverName} or null;
        # Read, not written -- level-name lives wherever that server's
        # own server.nix sets it (server.properties' actual on-disk
        # world folder name), which has nothing to do with this vars.
        # minecraft.worlds entry's own attr-set key.
        levelName = config.services.minecraft-servers.servers.${serverName}.serverProperties.level-name or "world";
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

        extraFiles =
          lib.optionalAttrs (hardcoreDims != [ ]) {
            "plugins/Skript/scripts/hardcore-permadeath.sk" = pkgs.writeText "hardcore-permadeath.sk" (
              mkHardcoreScript hardcoreDims
            );
          }
          // lib.optionalAttrs (spawn.startIn != null || spawn.loginIn != null) {
            # startIn -> first-spawn-override (only ever the player's
            # very first join). loginIn -> join-destination (every join
            # after that, forever). Either unset means Multiverse's own
            # default for that case (server.properties spawn on first
            # join; last logout location on every subsequent one).
            # safe-location search radius set to 0 to bypass Multiverse's
            # safe-location veto entirely, since a void/flat world (no
            # solid ground under the exact spawn point) otherwise fails
            # with "UNSAFE_LOCATION" and silently falls back to whatever
            # location the player last logged out from -- confirmed in
            # the wild 2026-08-09 with hub's void floor.
            "plugins/Multiverse-Core/config.yml".value = {
              spawn =
                lib.optionalAttrs (spawn.startIn != null) {
                  first-spawn-override = true;
                  first-spawn-location = parseDestination spawn.startIn;
                }
                // lib.optionalAttrs (spawn.loginIn != null) {
                  enable-join-destination = true;
                  join-destination = parseDestination spawn.loginIn;
                };
              teleport = {
                safe-location-horizontal-search-radius = 0;
                safe-location-vertical-search-radius = 0;
              };
            };
          };
      in
      {
        extraStartPre =
          mkTrashScript (map (d: d.dimName) dims)
          + lib.optionalString (nonMv != null && nonMv.value.regenerate) (mkRegenScript levelName);
        extraStartPost =
          mkServerScript serverName dims
          + lib.concatMapStringsSep "\n" mkGamemodePermCmds creativeDims
          + lib.optionalString (creativeDims != [ ]) mkTeleportPermCmd
          + mkOpsCmds serverName;
      }
      // lib.optionalAttrs (extraSymlinks != { }) { symlinks = extraSymlinks; }
      // lib.optionalAttrs (extraFiles != { }) { files = extraFiles; }
      // lib.optionalAttrs (nonMv != null && nonMv.value.seed != null) {
        serverProperties.level-seed = nonMv.value.seed;
      }
    ) dimsByServer;

    # Overrides the base services.minecraft-servers module's own
    # WantedBy=multi-user.target (set automatically whenever a server's
    # enable = true) with vars.minecraft.servers.<name>.autostart's
    # opt-in default instead. Every server named anywhere in this module
    # (worlds/ops/spawn) gets an explicit entry -- mkForce so a bare
    # `enable = true` with no autostart declared actually ends up
    # NOT auto-starting, not just falling back to the base module's own
    # always-on default.
    systemd.services = lib.listToAttrs (
      map (serverName: {
        name = "minecraft-server-${serverName}";
        value.wantedBy = lib.mkForce (
          lib.optional (spawnCfg.${serverName}.autostart or false) "multi-user.target"
        );
      }) allServerNames
    );
  };
}
