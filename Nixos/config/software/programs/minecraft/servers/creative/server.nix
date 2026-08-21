# &desc: "Creative server's serverProperties -- port, default creative/peaceful fallback, and the unmanaged vanilla-bootstrap level-name."

{ ... }:

{
  services.minecraft-servers.servers.creative.serverProperties = {
    server-port = 25565;
    gamemode = "creative"; # fallback/default world gamemode -- no survival here
    difficulty = "peaceful"; # fallback difficulty -- no survival here
    # TEMPORARY -- forces every join to gamemode (creative) at the same
    # early connection point vanilla's own flying-ability check runs,
    # fixing a stale abilities.flying=true vs. stored gamemode mismatch
    # that was kicking a real login before Multiverse's own gamemode
    # enforcement (which only fires post-join) got a chance to fix it.
    # Revert to unset once confirmed working -- see tickfreeze.nix
    # testing session 2026-08-10.
    force-gamemode = true;
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
    max-players = 5;
    view-distance = 8;
    simulation-distance = 5;

    # RCON -- lets `mcli rcon creative` (Scripts/Minecraft) and mcrcon
    # send console commands without attaching to the tmux console. Port
    # opened via ports.nix, same mechanism as BlueMap's own port.
    #
    # The password below is real and genuinely secret (unlike this file's
    # other values) -- it's plaintext here only because pinning it in Nix
    # is the one way to set it without --impure breaking a plain `pacnix
    # rebuild` (an external, non-flake file read requires that flag).
    # config/github/replacements.nix has a matching entry that swaps this
    # exact line for a placeholder in the copy `dotfiles-backup` actually
    # pushes to GitHub -- same mechanism already used for the MAC address
    # and gitCommitEmail. Rotate by editing both this line and that one
    # together; `mcli rcon` reads the live value straight out of the
    # rendered server.properties, not a separate copy, so nothing else
    # needs updating.
    enable-rcon = true;
    "rcon.port" = 25575;
    "rcon.password" = "changeme";
  };
}
