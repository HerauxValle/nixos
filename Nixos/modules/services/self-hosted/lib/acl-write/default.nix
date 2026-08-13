# &desc: "ACL write-grant schema -- grants for dedicated-user services to write into /home-rooted leaf paths they don't own, shared machine-level option."

{ lib, ... }:

# Schema only -- logic lives in ./acl-write.nix, the mechanism itself is
# ./mk-acl-write.nix (a plain function, re-exported from ../../self-hosted.nix
# as mkAclWrite same as every other lib/ helper). Sibling to
# ../acl-traversal/'s own real options/config exception, same reasoning:
# a shared, machine-level surface for something genuinely not any single
# service's own data -- which dedicated system user can write into which
# leaf directory it doesn't own.
#
# NOT the same problem ../acl-traversal/ solves (see its own top comment):
# that one is execute-only traversal through *ancestor* directories, and
# its own description explicitly rules out /home-rooted paths since
# ProtectHome=tmpfs+BindPaths already solves visibility there. This is
# for the leaf directory itself, once visible: real rwx, because
# visibility (BindPaths) isn't permission (ACLs still gate the actual
# read/write). Real case that found this: qbittorrent's own
# paths.save/temp/export/finished (config.vars.system.mountpoints.device.
# storage.path's own Torrents/* tree) are real, pre-existing directories
# owned by config.vars.identity.username, whose ACLs only ever granted
# that user's own group rwx -- the dedicated qbittorrent system user had
# nothing beyond `other::r-x`, so a freshly-added torrent needing to
# write piece data errored out instantly.
{
  imports = [ ./acl-write.nix ];

  options.vars.services.selfHosted.aclWriteGrants = lib.mkOption {
    # Keyed by systemd unit name (e.g. "qbittorrent") -- the key itself
    # *is* the unit, so each service's own wiring file just sets its own
    # vars.services.selfHosted.aclWriteGrants.<name> entry against its
    # own real paths, instead of a flat list where every entry has to
    # repeat which unit it belongs to.
    type = lib.types.attrsOf (lib.types.listOf (lib.types.submodule {
      options = {
        group = lib.mkOption {
          type = lib.types.str;
          description = "The dedicated system user's own group (e.g. \"qbittorrent\") to grant rwx to, via a real group ACL entry.";
        };
        path = lib.mkOption {
          type = lib.types.str;
          description = "The real leaf directory the dedicated user needs to read/write, not just traverse -- gets a recursive rwx group grant plus a default ACL entry so anything created under it afterwards inherits the same grant.";
        };
      };
    }));
    default = { };
    description = ''
      Real, machine-level ACL write grants, one list per systemd unit --
      each entry gives that unit's own dedicated system user's group real
      rwx (recursive, plus a default ACL entry for future contents) into
      one real leaf directory it doesn't own, re-applied every time the
      unit starts via a genuinely separate, unhardened oneshot unit
      (acl-write-<unit>.service).

      SEPARATE unit, not appended to <unit>.service's own preStart --
      same real, reproducible bug ../acl-traversal/acl-traversal.nix's
      own top comment documents: a dedicated-user service typically runs
      with PrivateUsers=true (part of its own hardening), and `setfacl`
      executed *inside* that private user namespace hits a UID-mapping
      artifact that collides with the real group entry it's trying to
      write ("Malformed access ACL ... Duplicate entries"). A separate
      oneshot ordered strictly before <unit>.service (Before=/RequiredBy=)
      runs as plain root instead, sidestepping the whole problem.

      WHEN TO ADD AN ENTRY: only once BindPaths (or an equivalent) has
      already made `path` visible inside the target unit's own sandbox
      and a real check (attempting to write as the dedicated user, e.g.
      via `sudo systemd-run` with the same ProtectHome/BindPaths/User
      properties as the real unit) confirms it still can't write --
      visibility isn't permission, and this only ever fixes the latter.
    '';
  };
}
