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

    # Random test seed -- swap for a researched one whenever, no
    # downside to changing it later: regenerate just wipes and
    # rebootstraps against whatever's here at the time.
    seed = "3008458520959580222";

    # true + rebuild wipes the world (archived to trash/, not deleted)
    # on every single start until set back to false -- flip it on,
    # rebuild once to get a fresh attempt, then flip back off so normal
    # restarts stop wiping progress.
    regenerate = false;
  };
}
