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
    # Both maxed out (32 is vanilla's actual ceiling for each) -- these
    # are just the server-side cap, not what you'll actually render.
    # Your client's own render-distance setting decides the effective
    # distance below that ceiling, and switching that is instant
    # (no server restart) unlike changing these.
    view-distance = 32;
    simulation-distance = 32;

    # Pure bandwidth optimization -- compresses packets above this size,
    # zero gameplay effect. From the "6 config files performance" video
    # review -- see files.nix/plugins.nix comments for the rest of that
    # batch and what was rejected from it.
    network-compression-threshold = 256;

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
