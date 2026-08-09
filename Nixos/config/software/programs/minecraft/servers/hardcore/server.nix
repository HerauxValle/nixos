# &desc: "Hardcore server's serverProperties -- port, hardcore=true (forces difficulty to hard, one life), single vanilla-bootstrapped world."

{ ... }:

{
  services.minecraft-servers.servers.hardcore.serverProperties = {
    server-port = 25566; # creative already owns 25565
    hardcore = true; # forces difficulty=hard; death drops you into spectator mode permanently, not a ban
    gamemode = "survival";
    # difficulty left unset -- hardcore=true forces it to hard regardless.
    level-name = "world"; # single vanilla-bootstrapped world, no Multiverse
    online-mode = true;
    white-list = false;
    pvp = false; # solo play
    view-distance = 32;
    simulation-distance = 12;

    # RCON -- same purpose as creative's (mcli rcon / mcrcon). Password
    # generated fresh for this server, not reused from creative -- see
    # creative/server.nix's comment for why it's plaintext here and how
    # rotation works (config/github/replacements.nix has the matching
    # redaction entry, added alongside this one).
    enable-rcon = true;
    "rcon.port" = 25576;
    "rcon.password" = "changeme";
  };
}
