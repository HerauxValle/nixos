# &desc: "Minecraft settings -- eula acceptance, dataDir inside the Minecraft Casket vault's servers/ subdir."

{ ... }:

# eula/dataDir are real options on services.minecraft-servers itself
# (not per-server), so they're set once here instead of duplicated in
# servers/hardcore.nix/servers/testworld.nix. dataDir lives inside the
# Minecraft Casket vault (config/system/autostart.nix's "minecraft" job
# -- create it with `cas Minecraft create` + `cas Minecraft 2fa on`
# before enabling any server), under servers/ specifically so prism/
# can hold Prism Launcher config alongside it later.
{
  services.minecraft-servers = {
    eula = true;
    dataDir = "/home/herauxvalle/Images/Minecraft/servers";
  };
}
