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
    jvmOpts = "-Xmx8G -Xms1G -Dpaper.disableChannelLimit=true";
  };
}
