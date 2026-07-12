{ config, lib, pkgs, ... }:

# Wiring only -- for every real grant declared in
# vars.selfHosted.aclTraversal (config/self-hosted/acl-traversal.nix
# holds the real values), a real, SEPARATE systemd oneshot unit per
# target unit (acl-traversal-<unit>.service, not a preStart line
# appended onto <unit>.service itself) runs mkAclTraversal's
# preStartScript, ordered strictly before <unit>.service via
# Before=+RequiredBy=.
#
# Not appended into <unit>.service's own preStart (the first thing
# tried) -- real, reproducible bug found on a live run: qbittorrent's
# own PrivateUsers=true (part of the wrapped module's own hardening,
# untouched here) puts the unit in a private user namespace, and
# `setfacl` run *inside* that namespace sees a UID-mapping artifact
# (`user:4294967295:...`, the "unmapped" sentinel) that collides with
# the real `u:qbittorrent:...` entry it's trying to write, failing with
# "Malformed access ACL ... Duplicate entries". A separate, unhardened
# oneshot (no PrivateUsers, runs as plain root -- root doesn't need any
# ACL grant to traverse anything, so this sidesteps the whole problem)
# fixes it outright, and also resolves a real ordering bug the
# preStart-append approach had along the way: <unit>.service's own
# preStart already runs requireMounts' mount check (from
# mk-from-native/services.nix), and that check needs the ACL grant to
# have *already* happened -- as two contributions merged into the same
# `types.lines`, forcing the right order needed lib.mkBefore and still
# didn't fix the real PrivateUsers issue underneath. A fully separate,
# strictly-ordered unit sidesteps both problems at once.
#
# config.systemd.services = lib.mapAttrs' (...) byUnit -- deliberately
# NOT `config = lib.mkMerge (map (grant: {...}) aclTraversal)`, which
# was the very first thing tried and caused a real, reproducible
# infinite recursion: assigning a dynamically-shaped `lib.mkMerge`
# result (its own length depending on
# config.vars.selfHosted.aclTraversal) directly as this module's
# top-level `config` forces Nix to resolve that list's length just to
# determine this module's own config *structure*, before
# vars.selfHosted.aclTraversal itself can be considered resolved --
# genuinely circular. Confirmed by bisection (this session): a *static*
# top-level key (here, the literal attribute name `systemd.services`)
# whose *value* is computed dynamically via `lib.mapAttrs'` doesn't have
# this problem -- only the top-level shape of `config` itself needs to
# be static, nothing below it does. lib.groupBy first (not a raw
# builtins.listToAttrs) so multiple grants aiming at the same unit merge
# into one acl-traversal-<unit>.service instead of the later one
# silently dropping the earlier one.

let
  selfHosted = import ../../self-hosted.nix { inherit lib pkgs; };
  byUnit = lib.groupBy (grant: grant.unit) config.vars.selfHosted.aclTraversal;
in
{
  config.systemd.services = lib.mapAttrs'
    (unit: grants: lib.nameValuePair "acl-traversal-${unit}" {
      description = "ACL traversal grants for ${unit}, applied before it starts";
      before = [ "${unit}.service" ];
      requiredBy = [ "${unit}.service" ];
      path = [ pkgs.acl ];
      script = lib.concatMapStringsSep "\n"
        (grant:
          (selfHosted.mkAclTraversal {
            inherit (grant) user baseDir path;
            grant = true;
          }).preStartScript)
        grants;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
      };
    })
    byUnit;
}
