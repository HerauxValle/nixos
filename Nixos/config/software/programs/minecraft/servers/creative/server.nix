# &desc: "Creative server's serverProperties -- port, default creative/peaceful fallback, and the unmanaged vanilla-bootstrap level-name."

{ ... }:

{
  services.minecraft-servers.servers.creative.serverProperties = {
    server-port = 25565;
    gamemode = "creative"; # fallback/default world gamemode -- no survival here
    difficulty = "peaceful"; # fallback difficulty -- no survival here
    # Only affects the ONE vanilla-bootstrapped default world (whatever
    # level-name says) at first-ever boot -- Multiverse-created worlds
    # (worlds.nix) go through a different code path entirely. level-name
    # is deliberately NOT one of those declared groups: that vanilla-
    # bootstrap folder is never in vars.minecraft.worlds, so
    # minecraft-worlds.nix's trash-on-removal logic never touches it
    # either (it only ever acts on names it itself created).
    level-name = "bootstrap";
    online-mode = true; # keep true unless you have a specific reason not to
    white-list = false; # or true if you want to gate join access
    pvp = false;
    view-distance = 32;
    simulation-distance = 12;
  };
}
