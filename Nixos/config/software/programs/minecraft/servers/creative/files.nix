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
    files."server-icon.png" = ../../icons/creative.png;

    # Tailored for creative's multi-world context -- shows which world
    # you're actually in (hub/redstone/building/temp are genuinely
    # different places you jump between, unlike hardcore's single
    # world). No established palette existed for this server before
    # (unlike hardcore's gold/gray AdvancedServerList MOTD), so this
    # picks its own bright aqua->lime gradient fitting a
    # creative/building server, with its own tagline mirroring
    # hardcore's "One life. No second chances." (the opposite framing --
    # total freedom instead of total risk). Only the keys that matter are set here;
    # TAB auto-patches in its own defaults for everything else on first
    # load. MiniMessage gradients need components.minimessage-support
    # (TAB's own shipped default: true, left untouched here). Verify
    # against the real generated plugins/TAB/config.yml after first boot.
    files."plugins/TAB/config.yml" = {
      format = pkgs.formats.yaml { };
      value = {
        header-footer = {
          enabled = true;
          designs.default = {
            header = [
              "<gray><strikethrough>                                        </strikethrough></gray>"
              "<gradient:#00E5FF:#7CFC00><bold>✦ CREATIVE ✦</bold></gradient>"
              "<gray><italic>Unlimited canvas. No limits, no consequences.</italic></gray>"
              "<aqua>World: <white>%world%</white></aqua>"
              ""
            ];
            footer = [
              ""
              "<gray>Ping <white>%ping%ms</white>  <dark_gray>|</dark_gray>  <gray>Mem <white>%memory-used%</white>/<white>%memory-max%</white>MB</gray>"
              "<green>%time%</green>"
              "<gray><strikethrough>                                        </strikethrough></gray>"
            ];
          };
        };
        playerlist-objective = {
          enabled = true;
          value = "%ping%";
          fancy-value = "<aqua>%ping%ms</aqua>";
        };
        # Not clustered with anything else -- avoids stray
        # RedisBungee-lookup warnings on boot.
        proxy-support.enabled = false;
        # REQUIRED -- without this, TAB's own config-updater treats the
        # file as an old/unversioned config on load and rewrites
        # designs.default's header/footer back to empty arrays,
        # silently discarding everything set above (confirmed the hard
        # way 2026-08-11 on hardcore's identical config -- see that
        # file's own comment). 7 is this TAB version's (6.1.2) own
        # current config-version, confirmed from its shipped default
        # config.yml.
        config-version = 7;
      };
    };

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
