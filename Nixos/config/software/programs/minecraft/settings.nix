# &desc: "Minecraft settings -- eula acceptance, dataDir inside the Minecraft Casket vault's servers/ subdir."

{ config, lib, pkgs, ... }:

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
  vars.minecraft.dataDir = "/home/herauxvalle/Images/Minecraft/servers";
  vars.minecraft.premiumAddons = "/home/herauxvalle/Images/Minecraft/premium";

  services.minecraft-servers = {
    enable = true;
    eula = true;
    dataDir = config.vars.minecraft.dataDir;
  };

  # dataDir's parent (the vault mount point) is deliberately root-owned,
  # which makes it a root-owned dir nested under herauxvalle-owned Images/
  # -- systemd-tmpfiles refuses to manage ("unsafe path transition") any
  # `d` rule underneath an ownership jump like that, so it can't be the
  # thing creating dataDir/<server>. This oneshot does the same job by
  # hand instead, scoped only to servers/ and below -- never touches the
  # mount point itself.
  #
  # It also (re-)sets the ACL on ~herauxvalle itself (0700, so the
  # minecraft user otherwise can't even traverse into it to reach dataDir)
  # every time this runs, rather than via a one-off systemd.tmpfiles rule:
  # NixOS's own tmpfiles rules reset ~herauxvalle back to 0700 on every
  # boot, and that chmod silently zeroes the ACL's mask entry (even though
  # the named-user entry itself survives), so a static tmpfiles-time ACL
  # doesn't stay effective. Reapplying it last, right before the server
  # starts, sidesteps the ordering problem entirely.
  systemd.services =
    {
      "minecraft-servers-dirs" = {
        description = "Create per-server directories under the Minecraft dataDir";
        after = [ "home-herauxvalle-Images-Minecraft.mount" ];
        requires = [ "home-herauxvalle-Images-Minecraft.mount" ];
        before = map (n: "minecraft-server-${n}.service") enabledServers;
        wantedBy = map (n: "minecraft-server-${n}.service") enabledServers;
        serviceConfig.Type = "oneshot";
        path = [ pkgs.acl ];
        script = ''
          setfacl -m u:${cfg.user}:x,m::x /home/herauxvalle
        ''
        + lib.concatMapStringsSep "\n" (n: ''
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
      # Also disable: a private UID namespace can stop the named-user ACL
      # entry above (u:minecraft:--x on ~herauxvalle) from resolving
      # correctly, since the kernel's ACL check may see a remapped/unmapped
      # UID rather than minecraft's real one.
      serviceConfig.PrivateUsers = lib.mkForce false;

      # A rebuild must never touch a running server on its own -- any
      # config/plugin-jar edit changes that unit's derivation, and
      # without this NixOS would stop (world save across every world,
      # 30-60s+) then restart it on every single `pacnix rebuild`.
      # Generic across every current and future server (genAttrs over
      # enabledServers, not one flag per server/package.nix) so this
      # can't quietly go missing the next time a server gets added --
      # `mcli start/stop/restart/fail <name>` (Scripts/Minecraft) are the
      # only things that should ever start/stop/restart these units now.
      # The unit FILE itself still gets rewritten by every rebuild same
      # as always -- this only stops systemd from acting on that change
      # by itself; `mcli restart <name>` (or a real reboot) is still what
      # actually picks up a changed unit.
      restartIfChanged = lib.mkForce false;
      stopIfChanged = lib.mkForce false;
    });
}
