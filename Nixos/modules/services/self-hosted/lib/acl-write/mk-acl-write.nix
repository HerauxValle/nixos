# &desc: "ACL write grant builder -- recursive rwx group grant + default ACL on a leaf directory, real setfacl primitives, revocable."

{ lib, pkgs }:

# Sibling to ../acl-traversal/, deliberately NOT a generalization of it:
# acl-traversal grants execute-only ("X") traversal through *ancestor*
# directories a dedicated user doesn't own, and its own options
# description explicitly rules out /home-rooted paths (ProtectHome=tmpfs
# +BindPaths already solves traversal there). This solves a different,
# real problem found live on qbittorrent: BindPaths makes a /home-rooted
# leaf directory (config.vars.system.mountpoints.device.storage.path's
# own Torrents/* tree) visible inside the sandbox, but visibility isn't
# write permission -- that tree's real ACLs only ever granted rwx to
# config.vars.identity.username's own user+group, leaving a dedicated
# service user (qbittorrent) with `other::r-x` and no way to write new
# data into it. Confirmed live: a freshly-added torrent errored
# instantly while pre-existing 100%-complete ones in the same tree were
# unaffected (they never needed to write).
#
# grant = true: `setfacl -R -m g:${group}:rwx` on `path` itself
# (recursive, covers whatever's already inside) plus a `d:` default
# entry (`setfacl -R -m d:g:${group}:rwx`, so anything created under
# `path` *after* this runs inherits the grant automatically, not just
# what existed at grant time). Confirmed idempotent, same primitive
# ../acl-traversal/mk-acl-traversal.nix already relies on for the same
# claim.
#
# grant = false: actively *removes* both the regular and default entry
# (`setfacl -x`/`setfacl -x d:`), not just omits granting them -- same
# "properly update on reload" requirement as acl-traversal's own
# revokeScript.
#
# preStartScript only (no tmpfilesRules/revokeScript split the way
# acl-traversal has) -- unlike an ancestor directory that's stable once
# mounted, re-running this every service start costs nothing extra
# (idempotent setfacl) and sidesteps having to reason about whether a
# given mount is "stable enough" for an activation-time-only grant.
# Needs pkgs.acl on the calling unit's own `path`.
{ group, path, grant }:
{
  preStartScript =
    if grant then
      ''
        ${pkgs.acl}/bin/setfacl -R -m g:${group}:rwx "${path}"
        ${pkgs.acl}/bin/setfacl -R -m d:g:${group}:rwx "${path}"
      ''
    else
      ''
        ${pkgs.acl}/bin/setfacl -R -x g:${group} "${path}" 2>/dev/null || true
        ${pkgs.acl}/bin/setfacl -R -x d:g:${group} "${path}" 2>/dev/null || true
      '';
}
