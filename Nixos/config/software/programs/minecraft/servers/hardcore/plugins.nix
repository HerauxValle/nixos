# &desc: "Hardcore server's plugin jars -- Chunky (pre-gen), BlueMap (fog-of-war config, see files.nix), GrimAC (movement anti-cheat, pure protection), ClearLaggEnhanced (periodic item/entity cleanup), PlayTimeManager (pure stats), VoxyServerSide (nerfed lodStreamRadius, see files.nix), MCPanel (web console, port 8090 -- see ports.nix). DiscordSRV commented out (not currently wanted). Spark is bundled with Paper 1.21+ already, no jar needed; AntiXray skipped, Paper ships it enabled by default. All chosen for zero gameplay advantage/cheating/non-vanilla content -- see conversation for the full reasoning."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore.symlinks = {
    "plugins/Chunky.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/fALzjamp/versions/MdY6JATr/Chunky-Bukkit-1.5.3.jar";
      hash = "sha256-Uw0sdDCpajmVc5G3CIvhRNqjEI92ZYltHCOqjdSvMvM=";
    };
    # Commented out for now, not currently wanted -- uncomment to re-add.
    # "plugins/DiscordSRV.jar" = pkgs.fetchurl {
    #   url = "https://cdn.modrinth.com/data/UmLGoGij/versions/ATlquwiT/DiscordSRV-Build-1.30.5.jar";
    #   hash = "sha256-7y+h8usUbHx3QStxkKfdM/H8kSgmg/5FQHc5VUyK7+8=";
    # };
    "plugins/BlueMap.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/swbUV1cr/versions/g7xgp4Xr/bluemap-5.23-spigot.jar";
      hash = "sha256-NZpG20Tj4WbH8RTxuWYwONsL1bX8NXJlF/nh2z6oCew=";
    };
    # Detects/reverts illegal movement (noclip/fly/speed) -- pure
    # protection against actual client-side cheats or desync glitches,
    # zero effect on legitimate play.
    "plugins/GrimAC.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/LJNGWSvH/versions/fbt7nJt5/grimac-bukkit-2.3.74-2614909.jar";
      hash = "sha256-viF0HZxw9RJBGCgdAJsagxZaIR9TrxDa1LMZb/U8l+0=";
    };
    "plugins/ClearLaggEnhanced.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/KAaZvh09/versions/nlLigbcJ/ClearLaggEnhanced-26.8.0.jar";
      hash = "sha256-MdLk5dxwwix8ssPNA/n3+M839a3aZJ+ZAHIPc4/L4Pk=";
    };
    # Pure stats -- /playtime and friends, no gameplay effect.
    "plugins/PlayTimeManager.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/OzCiibPq/versions/C0SSVnbh/PlayTimeManager-3.6.5.jar";
      hash = "sha256-H3HuF8g5kCVKJUEZNNG8sEyDnVBTIdhMxJRpkEQVCKo=";
    };

    # NOT added: AntiXray -- Paper's own paper-world-defaults.yml already
    # ships anti-xray enabled by default (anticheat.anti-xray.enabled:
    # true, engine-mode: 2), confirmed via PaperMC's own docs. A plugin
    # would be redundant.

    # Streams real generated (not fake/synthetic) chunk data as LODs
    # beyond simulation-distance -- a genuine foreknowledge advantage if
    # left at its default 256-chunk radius (structures included, since
    # it's real chunk data). lodStreamRadius in files.nix's
    # vss-server-config.json is the only real nerf knob -- see that
    # file's own comment for the caveat about client-side override.
    "plugins/VoxyServerSide.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/84zcagOb/versions/zI7Q9rlu/voxy-server-side-paper.jar";
      hash = "sha256-QLM8ASeYLZrW1zzCKjCNpwsxO9C5+agfMc043cnj3Ds=";
    };

    # Web console (browser-based, its own built-in HTTP server, no RCON
    # needed). Officially only lists support through 26.1.2 -- it's a
    # pure Bukkit-API/HTTP-server tool with no NMS/version-specific game
    # logic though, so likely still works unofficially on 26.2. Verify
    # after first boot; revert to a manual mcrcon/tmux console if it
    # doesn't load cleanly.
    "plugins/MCPanel.jar" = pkgs.fetchurl {
      url = "https://hangarcdn.papermc.io/plugins/VenDooM/MC-Server-Admin-Panel/versions/1.2.4/PAPER/MCPanel-1.2.4.jar";
      hash = "sha256-jiOzvdawid0TnFnPzLKC8KPeAeNYrGZwrwrTgasa+So=";
    };
  };
}
