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
    # Lowered from vanilla's 32/32 ceiling after a GPU hang (Xid 31/109
    # MMU faults) while running Iris + a heavy shaderpack at max shadow
    # distance against this server's original 32-chunk cap -- these are
    # just the server-side cap, not what you'll actually render. Your
    # client's own render-distance setting can go lower than this
    # freely (instant, no restart); it just can't go higher.
    # ViewDistanceTweaks (plugins.nix) can override these live via /vdt
    # without a restart -- reverts to these values on the next restart.
    view-distance = 8;
    simulation-distance = 5;

    # Pure bandwidth optimization -- compresses packets above this size,
    # zero gameplay effect. From the "6 config files performance" video
    # review -- see files.nix/plugins.nix comments for the rest of that
    # batch and what was rejected from it.
    network-compression-threshold = 256;

    # Tool Trims' companion asset pack -- the datapack zip (plugins.nix's
    # world/datapacks/ToolTrims.zip) already contains both the data/
    # (mechanics) and assets/ (trim textures) halves in one archive, but
    # Minecraft only reads world/datapacks/ for the data half -- the
    # assets half has to be separately served as an actual resource
    # pack for the new trim patterns to render (confirmed via the
    # in-game warning: "The required assets weren't detected... use it
    # as a resource pack"). Same exact file/URL as the datapack, just
    # pointed at directly from Modrinth's CDN since it's already public
    # and stable there -- no need to re-host it ourselves. sha1 (not
    # sha256 -- this is the one vanilla server-properties key that's
    # still SHA-1) confirmed against Modrinth's own file hash listing.
    resource-pack = "https://cdn.modrinth.com/data/uXeEiQk1/versions/26fWzOv5/tool-trims-v3.0.7-for-1.21.11%2B.zip";
    "resource-pack-sha1" = "01818424833cfd314b5c269894468abf8a04799e";
    require-resource-pack = false;

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
