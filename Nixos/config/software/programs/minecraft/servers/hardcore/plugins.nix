# &desc: "Hardcore server's plugin jars -- Chunky (pre-gen), BlueMap (fog-of-war config, see files.nix), GrimAC (movement anti-cheat, pure protection), ClearLaggEnhanced (periodic item/entity cleanup), PlayTimeManager (pure stats), VoxyServerSide (nerfed lodStreamRadius, see files.nix), MCPanel (web console, port 8091 -- see ports.nix). DiscordSRV commented out (not currently wanted). Spark is bundled with Paper 1.21+ already, no jar needed; AntiXray skipped, Paper ships it enabled by default. All chosen for zero gameplay advantage/cheating/non-vanilla content -- see conversation for the full reasoning."

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
    # PAPER build, not Spigot -- the Spigot jar caused BlueMap to fail
    # world-detection entirely and disable itself ("no valid maps
    # configured") on first boot 2026-08-10, confirmed via its own log
    # warning ("you are using the SPIGOT version of BlueMap ... Things
    # will likely not work correctly!"). Same hash as creative's own
    # BlueMap entry -- confirms this is the right jar.
    "plugins/BlueMap.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/swbUV1cr/versions/K5U1ASjn/bluemap-5.23-paper.jar";
      hash = "sha256-M5VU11ztqzVON2Z3z8cwjEmZUpFYSejimUcY5KFT1k4=";
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
    # left at its default 512-chunk radius (structures included, since
    # it's real chunk data). lodDistanceChunks in files.nix's
    # vss-server-config.json is the only real nerf knob.
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

    # Permissions plugin -- fixes PlayTimeManager's "LuckPerms plugin
    # configured but not found" warning, and lets you grant fine-grained
    # command permissions to non-op players (e.g. for command-alias/
    # logic plugins below) without giving full op. NOT wired to grant
    # any gameplay-affecting permission node by default -- op status
    # (gamemode/etc.) stays exactly as restricted as before (ops.nix).
    # Same jar/hash as creative's own LuckPerms entry.
    "plugins/LuckPerms.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vebnzrzj/versions/b0mk8uS6/LuckPerms-Bukkit-5.5.71.jar";
      hash = "sha256-Sc7LZvof0ioTMDmkkOnB5QlaI4581m650qFv5siXVQ0=";
    };

    # Commented out -- no alias in mind yet. Simple command ALIASING
    # (shortcut to an existing command, e.g. /hub -> /mvtp hub) needs no
    # plugin at all -- see files.nix's commented commands.yml block.
    # This is only for actual NEW commands with their own logic/tab-
    # completion. Skript is the example here since it's already a known
    # dependency elsewhere in this repo (minecraft-worlds.nix's hardcore
    # permadeath script) -- same jar/hash, so uncommenting this is a
    # known-good starting point, not unresearched. Tell me what you want
    # the command(s) to actually do and I'll help write the script +
    # grant the right (non-cheat) LuckPerms permission node for it.
    # "plugins/Skript.jar" = pkgs.fetchurl {
    #   url = "https://cdn.modrinth.com/data/xFNYAvMk/versions/9s2QlgIA/Skript-2.16.1.jar";
    #   hash = "sha256-g1ejSLJ82KLPdJmY5K0UvR3KMWACa9MELW0Xz7TJinA=";
    # };
  };
}
