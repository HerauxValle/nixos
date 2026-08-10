# &desc: "Hardcore server's world declaration -- multiverse=false, since there's no Multiverse plugin here; drives seed + on-demand regenerate for its single vanilla-bootstrapped default world."

{ ... }:

{
  # See modules/services/minecraft-worlds/lib/world-type.nix's own
  # `multiverse` option doc for exactly what does/doesn't apply in this
  # mode. hardcore=true (the real permadeath flag) already lives in
  # server.nix's serverProperties -- unaffected by this entry.
  vars.minecraft.worlds.hardcore = {
    server = "hardcore";
    multiverse = false;

    # Real survival seed -- deliberately picked knowing nothing about it
    # except the spawn island itself (never explored beyond that):
    # fairly large island, a village with a zombie villager ("dead
    # village"), cherry grove up top. Confirmed 2026-08-10.
    seed = "8907256489";

    # true + rebuild wipes the world (archived to trash/, not deleted)
    # on every single start until set back to false -- flip it on,
    # rebuild once to get a fresh attempt, then flip back off so normal
    # restarts stop wiping progress.
    regenerate = true;
  };
}
