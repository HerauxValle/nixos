# &desc: "Hardcore server's plugin jars -- Chunky (pre-gen), BlueMap (fog-of-war config, see files.nix), GrimAC (movement anti-cheat, pure protection), ClearLaggEnhanced (periodic item/entity cleanup). DiscordSRV commented out (not currently wanted). Spark is bundled with Paper 1.21+ already, no jar needed. All chosen for zero gameplay advantage/cheating/non-vanilla content -- see conversation for the full reasoning. TAB and a Prometheus exporter were also considered but have no working 26.2 build yet."

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
  };
}
