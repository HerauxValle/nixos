# &desc: "Hardcore server's package/version pin and enable/firewall toggles -- single vanilla world, no multi-world startup race, default TimeoutStartSec is fine."

{ pkgs, ... }:

{
  services.minecraft-servers.servers.hardcore = {
    enable = true;

    # Same reasoning as creative/package.nix -- nix-minecraft is required
    # for anything above the base module's v1.21.9 cap, and this matches
    # your Prism client's 26.2 pin.
    package = pkgs.paperServers.paper-26_2;

    # Enabled for non-local access from the same network
    openFirewall = true;

    # Same 100+ mod Fabric client as creative -- Paper's plugin-channel
    # cap kicks it with "Invalid custom payload payload!" without this
    # (see creative/package.nix's own comment for the full story).
    #
    # Aikar's flags (https://docs.papermc.io/paper/aikars-flags/, PaperMC's
    # own documented G1GC tuning) below -Xmx/-Xms -- Xms matches Xmx
    # (Aikar's own recommendation) so the heap never has to resize mid-run,
    # which is half the point of this tuning.
    jvmOpts = "-Xmx8G -Xms8G -Dpaper.disableChannelLimit=true "
      + "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 "
      + "-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch "
      + "-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M "
      + "-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 "
      + "-XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 "
      + "-XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 "
      + "-XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1";
  };
}
