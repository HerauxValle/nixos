# &desc: "Tick-freeze feature -- for every server with vars.minecraft.servers.<name>.tickFreeze set (not null), installs a Skript /stopserver on|off command (LuckPerms default-group permission tickfreeze.toggle, no op needed) plus a systemd sidecar service that polls RCON and freezes/unfreezes ticks (vanilla /tick freeze) while the server is empty. The daemon force-unfreezes the instant a player is online regardless of the toggle, so it can never advantage anyone who's actually playing -- it only controls what happens while nobody's around, keeping the in-game day count tied to real playtime instead of wall-clock idle time."

{ config, lib, pkgs, ... }:

let
  spawnCfg = config.vars.minecraft.servers;

  tickFreezeServers = lib.filterAttrs (_: s: (s.tickFreeze or null) != null) spawnCfg;

  mkSkriptScript =
    defaultEnabled:
    ''
      on script load:
      	set {tickfreeze::enabled} to ${if defaultEnabled then "true" else "false"}

      command /stopserver <text>:
      	permission: tickfreeze.toggle
      	permission message: &cYou don't have permission to do that.
      	trigger:
      		if arg-1 is "on":
      			set {tickfreeze::enabled} to true
      			send "&aTick-freeze armed -- ticks pause while no one's online."
      		else if arg-1 is "off":
      			set {tickfreeze::enabled} to false
      			send "&cTick-freeze disarmed -- server keeps ticking even while empty."
      		else if arg-1 is "status":
      			if {tickfreeze::enabled} is true:
      				send "STOPSERVER:1"
      			else:
      				send "STOPSERVER:0"
      		else:
      			send "&cUsage: /stopserver on|off"
    '';

  mkDaemonScript =
    serverName: port: password:
    pkgs.writeShellApplication {
      name = "minecraft-${serverName}-tickfreeze-daemon";
      runtimeInputs = [
        pkgs.mcrcon
        pkgs.gnugrep
      ];
      text = ''
        rcon() {
          mcrcon -H 127.0.0.1 -P ${lib.escapeShellArg (toString port)} -p ${lib.escapeShellArg password} "$1"
        }

        frozen=0
        while true; do
          players_out=$(rcon "list" 2>/dev/null || true)
          count=$(printf '%s' "$players_out" | grep -oP 'There are \K[0-9]+' || echo 0)

          status_out=$(rcon "stopserver status" 2>/dev/null || true)
          enabled=0
          printf '%s' "$status_out" | grep -q 'STOPSERVER:1' && enabled=1

          if [ "''${count:-0}" -gt 0 ]; then
            # Never freeze while anyone's online, regardless of the
            # toggle -- this is the guarantee that no advantage can ever
            # come from this feature.
            if [ "$frozen" -eq 1 ]; then
              rcon "tick unfreeze" >/dev/null 2>&1 || true
              frozen=0
            fi
          elif [ "$enabled" -eq 1 ]; then
            if [ "$frozen" -eq 0 ]; then
              rcon "tick freeze" >/dev/null 2>&1 || true
              frozen=1
            fi
          else
            if [ "$frozen" -eq 1 ]; then
              rcon "tick unfreeze" >/dev/null 2>&1 || true
              frozen=0
            fi
          fi

          sleep 10
        done
      '';
    };
in
{
  config = lib.mkIf (tickFreezeServers != { }) {
    services.minecraft-servers.servers = lib.mapAttrs (serverName: s: {
      symlinks."plugins/Skript.jar" = pkgs.fetchurl {
        url = "https://cdn.modrinth.com/data/xFNYAvMk/versions/9s2QlgIA/Skript-2.16.1.jar";
        hash = "sha256-g1ejSLJ82KLPdJmY5K0UvR3KMWACa9MELW0Xz7TJinA=";
      };

      files."plugins/Skript/scripts/tickfreeze.sk" = pkgs.writeText "tickfreeze.sk" (
        mkSkriptScript s.tickFreeze
      );

      extraStartPost =
        let
          SOCK = "/run/minecraft/${serverName}.sock";
          send = cmd: ''
            ${pkgs.tmux}/bin/tmux -S "${SOCK}" send-keys ${lib.escapeShellArg cmd} Enter
            sleep 1
          '';
        in
        send "lp group default permission set tickfreeze.toggle true";
    }) tickFreezeServers;

    systemd.services =
      # The daemon units themselves -- After/BindsTo is what stops each
      # one with its server; a unit can't pull itself in via after/
      # bindsTo alone, which is what the second half below is for.
      (lib.mapAttrs' (
        serverName: s:
        let
          rconPort = config.services.minecraft-servers.servers.${serverName}.serverProperties."rcon.port";
          rconPassword = config.services.minecraft-servers.servers.${serverName}.serverProperties."rcon.password";
          daemon = mkDaemonScript serverName rconPort rconPassword;
          mcService = "minecraft-server-${serverName}.service";
        in
        lib.nameValuePair "minecraft-${serverName}-tickfreeze" {
          description = "Tick-freeze poll daemon for ${mcService} (pauses ticks while no one's online)";
          after = [ mcService ];
          bindsTo = [ mcService ];
          serviceConfig = {
            ExecStart = "${daemon}/bin/minecraft-${serverName}-tickfreeze-daemon";
            Restart = "on-failure";
            RestartSec = 5;
          };
        }
      ) tickFreezeServers)
      # Makes each server's own unit start its tickfreeze sidecar
      # automatically whenever the server itself starts.
      // (lib.mapAttrs' (
        serverName: _:
        lib.nameValuePair "minecraft-server-${serverName}" {
          wants = [ "minecraft-${serverName}-tickfreeze.service" ];
        }
      ) tickFreezeServers);
  };
}
