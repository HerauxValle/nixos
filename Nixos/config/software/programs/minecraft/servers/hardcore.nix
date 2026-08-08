# &desc: "Hardcore Minecraft server -- survival, one life, port 25565. Disabled until the Minecraft vault exists (see autostart.nix)."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore = {

    # Toggled on as its active at this point in time
    enable = false;

    # The minecraft module itself does not expose anything above v1.21.9
    # nix-minecraft is essential to play the latest version here!
    package = pkgs.paperServers.paper-26_1_2;

    # Enabled for non-local access from the same network
    openFirewall = true;

    serverProperties = {
      server-port = 25565;
      gamemode = "survival"; # fallback/default world gamemode
      difficulty = "hard"; # fallback difficulty
      hardcore = false; # DO NOT set true here — Multiverse sets it per-world instead
      motd = "...";
      level-name = "world"; # your default/hub world
      online-mode = true; # keep true unless you have a specific reason not to
      white-list = false; # or true if you want to gate join access
      pvp = true;
      view-distance = 32;
      simulation-distance = 12;
    };

    symlinks = {
      "plugins/Multiverse-Core.jar" = pkgs.fetchurl {
        url = "https://github.com/Multiverse/Multiverse-Core/releases/download/5.7.3/multiverse-core-5.7.3.jar";
        hash = "sha256-yRp8LCWtfYeCV7CMmAOB6LX/uo32P69AIkK/tWoFiIQ=";
      };
      "plugins/Dynmap.jar" = pkgs.fetchurl {
        url = "https://cdn.modrinth.com/data/fRQREgAc/versions/ImNNT17B/Dynmap-3.7-beta-8-spigot.jar";
        hash = "sha256-h8YDXCy3O/Ivw0ynOMshotuJq18wvRBxzYCQgCoceLw=";
      };
    };
  };
}
