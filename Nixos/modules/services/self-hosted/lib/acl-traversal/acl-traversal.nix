{ config, lib, pkgs, ... }:

# Wiring only -- for every real grant declared in
# vars.selfHosted.aclTraversal (config/self-hosted/acl-traversal.nix
# holds the real values), append mkAclTraversal's preStartScript onto
# that grant's own target unit's preStart (NixOS's own preStart is a
# mergeable types.lines -- concatenates cleanly onto whatever that
# unit's own module already contributes, same mechanism
# mk-from-native/services.nix's own requireMounts check already relies
# on) and add pkgs.acl to that unit's path so setfacl is actually
# resolvable -- no caller has to remember either of these themselves.
#
# preStartScript specifically, not tmpfilesRules/revokeScript -- every
# real grant so far (qbittorrent's /run/media/<user>) targets an
# ancestor directory recreated fresh by something outside Nix's control
# (udisks2, on each drive mount event), so the grant has to be
# re-applied on every unit start, not just once per rebuild. See
# mk-acl-traversal.nix's own top comment for the full reasoning and the
# case where the other (activation-time) form is the right one instead.
#
# config.systemd.services = lib.mapAttrs (...) byUnit -- deliberately
# NOT `config = lib.mkMerge (map (grant: {...}) aclTraversal)`, which
# was the first thing tried and caused a real, reproducible infinite
# recursion: assigning a dynamically-shaped `lib.mkMerge` result
# (its own length depending on config.vars.selfHosted.aclTraversal)
# directly as this module's top-level `config` forces Nix to resolve
# that list's length just to determine this module's own config
# *structure*, before vars.selfHosted.aclTraversal itself can be
# considered resolved -- genuinely circular. Confirmed by bisection
# (this session): a *static* top-level key (here, the literal attribute
# name `systemd.services`) whose *value* is computed dynamically via
# `builtins.listToAttrs`/`lib.mapAttrs` doesn't have this problem --
# only the top-level shape of `config` itself needs to be static,
# nothing below it does. lib.groupBy first (not a raw
# builtins.listToAttrs) so multiple grants aiming at the same unit
# merge their preStart scripts instead of the later one silently
# dropping the earlier one (listToAttrs keeps only the first
# occurrence of a duplicate name).

let
  selfHosted = import ../../self-hosted.nix { inherit lib pkgs; };
  byUnit = lib.groupBy (grant: grant.unit) config.vars.selfHosted.aclTraversal;
in
{
  config.systemd.services = lib.mapAttrs
    (_unit: grants: {
      # lib.mkBefore, not a plain string -- real, confirmed-necessary
      # ordering. types.lines merges every module's preStart
      # contribution by priority, default priority for both this and
      # mk-from-native/services.nix's own requireMounts check. Without
      # forcing this one first, the generated script ran the mount
      # check on /run/media/<user>/Storage *before* this grant, so the
      # mount check itself failed (not because the drive wasn't really
      # mounted -- confirmed live, `mountpoint` from a plain root shell
      # said yes -- but because qbittorrent had no traversal rights into
      # /run/media/<user> yet, the exact thing this grant exists to
      # fix). mkBefore makes this always run first regardless of import
      # order between the two contributing modules.
      preStart = lib.mkBefore (lib.concatMapStringsSep "\n"
        (grant:
          (selfHosted.mkAclTraversal {
            inherit (grant) user baseDir path;
            grant = true;
          }).preStartScript)
        grants);
      path = [ pkgs.acl ];
    })
    byUnit;
}
