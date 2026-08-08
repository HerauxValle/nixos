# &desc: "Minecraft settings -- eula acceptance, dataDir inside the Minecraft Casket vault's servers/ subdir."

{ config, lib, ... }:

let
  cfg = config.services.minecraft-servers;
  enabledServers = lib.attrNames (lib.filterAttrs (_: s: s.enable) cfg.servers);
in

# eula/dataDir are real options on services.minecraft-servers itself
# (not per-server), so they're set once here instead of duplicated in
# servers/hardcore.nix/servers/testworld.nix. dataDir lives inside the
# Minecraft Casket vault (config/system/autostart.nix's "minecraft" job
# -- create it with `cas Minecraft create` + `cas Minecraft 2fa on`
# before enabling any server), under servers/ specifically so prism/
# can hold Prism Launcher config alongside it later.
{
  services.minecraft-servers = {
    enable = false;
    eula = true;
    dataDir = "/home/herauxvalle/Images/Minecraft/servers";
  };

  # ~herauxvalle is 0700, so the minecraft system user can't traverse into
  # it to reach dataDir above, even though everything below is already
  # world-readable/minecraft-owned. Grant traverse-only (no read) via ACL
  # instead of loosening the home dir's mode bit for everyone.
  systemd.tmpfiles.rules = [
    "a+ /home/herauxvalle - - - - u:minecraft:X,m::x"
  ];

  # dataDir's parent (the vault mount point) is deliberately root-owned,
  # which makes it a root-owned dir nested under herauxvalle-owned Images/
  # -- systemd-tmpfiles refuses to manage ("unsafe path transition") any
  # `d` rule underneath an ownership jump like that, so it can't be the
  # thing creating dataDir/<server>. This oneshot does the same job by
  # hand instead, scoped only to servers/ and below -- never touches the
  # mount point itself.
  systemd.services =
    {
      "minecraft-servers-dirs" = {
        description = "Create per-server directories under the Minecraft dataDir";
        after = [ "home-herauxvalle-Images-Minecraft.mount" ];
        requires = [ "home-herauxvalle-Images-Minecraft.mount" ];
        before = map (n: "minecraft-server-${n}.service") enabledServers;
        wantedBy = map (n: "minecraft-server-${n}.service") enabledServers;
        serviceConfig.Type = "oneshot";
        script = lib.concatMapStringsSep "\n" (n: ''
          mkdir -p "${cfg.dataDir}/${n}"
          chown ${cfg.user}:${cfg.group} "${cfg.dataDir}/${n}"
          chmod 0770 "${cfg.dataDir}/${n}"
        '') enabledServers;
      };
    }
    # nix-minecraft hardens every minecraft-server-<name>.service with
    # ProtectHome = true, which makes all of /home invisible to the unit --
    # unrelated to and stronger than any filesystem permission/ACL, and fatal
    # here since dataDir lives under /home/herauxvalle. Relax it back to
    # false for just these units (everything else in the module's hardening
    # list stays intact).
    // lib.genAttrs (map (n: "minecraft-server-${n}") enabledServers) (_: {
      serviceConfig.ProtectHome = lib.mkForce false;
    });
}
