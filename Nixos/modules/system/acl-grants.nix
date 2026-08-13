# &desc: "Declares config.vars.system.aclGrants -- per-directory POSIX ACL read+execute grants via a setfacl activation script, applied on every rebuild/boot."

{ config, lib, pkgs, ... }:

# One flat file -- same reasoning as ./openrazer.nix, doesn't need a
# default.nix/lib split for a single list of {user,path} grants. Real
# values live in config/system/acl-grants.nix.
#
# Unlike modules/services/self-hosted/lib/acl-traversal (ancestor-only,
# execute-only "X", built for a dedicated service user traversing down
# to a data dir it owns), this grants "rx" directly on the named path
# itself -- for the actual case of "let one specific human user browse
# into a directory owned by a different service user" (e.g. Dolphin
# into an Immich-owned folder).
#
# systemd-tmpfiles' own "a+" line type was tried first and confirmed
# *rejected*: it refuses any ACL entry whose path crosses an "unsafe
# path transition" (parent dir owned by a different user than the
# target -- exactly this case, immich:immich under herauxvalle-owned
# Media/), `systemd-tmpfiles --create` exits 73 and logs "Detected
# unsafe path transition ... during canonicalization" instead of
# applying the entry (confirmed directly, same rejection already
# present for the pre-existing Minecraft/servers and
# SelfHosted/QBitTorrent entries in the journal, so this isn't new
# breakage -- tmpfiles has just never actually been able to grant ACLs
# across an ownership boundary here). A plain activationScript calling
# setfacl directly has no such check and is confirmed to work; `-m`
# is additive/idempotent across repeated rebuilds the same way "a+"
# was meant to be.
{
  options.vars.system.aclGrants = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        user = lib.mkOption {
          type = lib.types.str;
          description = "Username to grant read+execute access to.";
        };
        path = lib.mkOption {
          type = lib.types.str;
          description = "Absolute path of the directory to grant access on.";
        };
      };
    });
    default = [ ];
    description = "Per-directory POSIX ACL rx grants for a specific user, applied via a setfacl activation script on every rebuild/boot.";
  };

  config = lib.mkIf (config.vars.system.aclGrants != [ ]) {
    system.activationScripts.aclGrants = lib.stringAfter [ "users" ] (
      lib.concatMapStringsSep "\n"
        (g: ''${pkgs.acl}/bin/setfacl -m u:${g.user}:rx,m::rx "${g.path}" 2>/dev/null || true'')
        config.vars.system.aclGrants
    );
  };
}
