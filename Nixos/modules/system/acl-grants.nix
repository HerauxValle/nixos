# &desc: "Declares config.vars.system.aclGrants -- per-directory POSIX ACL read+execute grants via systemd-tmpfiles, applied on every rebuild/boot."

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
# into an Immich-owned folder). systemd-tmpfiles "a+" is additive and
# idempotent across repeated rebuilds (confirmed pattern already in use
# for the acl-traversal helper).
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
    description = "Per-directory POSIX ACL rx grants for a specific user, applied via systemd-tmpfiles on every activation.";
  };

  config = {
    systemd.tmpfiles.rules =
      map (g: "a+ ${g.path} - - - - u:${g.user}:rx") config.vars.system.aclGrants;
  };
}
