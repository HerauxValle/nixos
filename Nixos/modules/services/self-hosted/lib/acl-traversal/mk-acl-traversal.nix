{ lib, pkgs }:

# STATUS: dormant, not dead. Originally written ahead of a confirmed
# need for Immich, which turned out not to need it after all
# (ProtectHome="tmpfs"+BindPaths was sufficient on its own, since
# mediaLocation lives under /home). qbittorrent.nix was the one real
# caller for a while -- back when paths.save/temp/export/finished lived
# under /run/media/<user>/Storage, a completely different mount
# ProtectHome has no effect on at all, where the dedicated qbittorrent
# system user genuinely had no traversal permission into
# /run/media/<user> (0750 root:root, confirmed directly -- systemd-run
# as the qbittorrent user, mountpoint check failed; as root, same check
# succeeded). Those paths have since moved onto config.vars.mountpoints
# (a /home-rooted mount), so ProtectHome+BindPaths covers qbittorrent
# too now and this grant is unused again -- kept for the next
# dedicated-user service that genuinely needs a non-/home path.
#
# grant = true: an execute-only ("X" -- POSIX ACL conditional execute:
# only applies to directories or files already executable for someone,
# never silently grants execute on a plain file, see acl(5)) entry for
# `user` on every ancestor directory between `baseDir` and `path`.
# Verified idempotent by real repetition (ran three times in a row
# against a live test directory, `getfacl` showed exactly one entry, not
# three).
#
# grant = false: actively *removes* that entry, not just omits granting
# it -- necessary for "properly update on reload" (a later rebuild that
# flips this to false must not leave a stale grant behind).
#
# Two different output shapes for two different real persistence
# characteristics, both real callers now confirmed to need:
#
# - tmpfilesRules/revokeScript: systemd-tmpfiles' own `a+`/`setfacl -x`
#   (see each output's own comment), wired into systemd.tmpfiles.rules /
#   system.activationScripts -- applies once per `nixos-rebuild switch`.
#   Correct for an ancestor directory that's stable once mounted (a
#   Casket vault under /home, say) -- `a` (systemd-tmpfiles' "replace"
#   line type, no `+`) was tried first for the revoke side and confirmed
#   *unsafe*: it requires a non-empty argument, and supplying anything
#   other than the exact real base ACL entries (which Nix can't know at
#   eval time) silently corrupted the reported group permission bits in
#   a real test (a `m::rwx` mask placeholder widened the effective group
#   permission from r-x to rwx). `setfacl -x` removes only the one named
#   entry, confirmed not to touch the mask or anything else, and
#   confirmed idempotent (exit 0 even when the entry was never granted).
# - preStartScript: the same two `setfacl` primitives (`-m`/`-x`
#   directly, no systemd-tmpfiles involved), meant to be embedded in a
#   systemd unit's own `preStart` (mergeable `types.lines`, same
#   mechanism mk-from-native/services.nix's own requireMounts check
#   uses) and re-run on *every service start*, not just once per
#   rebuild. Needed for exactly this: /run/media/<user> is recreated
#   fresh by udisks2 on each mount event, a genuinely different
#   directory each time even though the path string never changes -- an
#   activation-time-only grant wouldn't survive a drive unplug/replug.
#   Needs pkgs.acl on the calling unit's own `packages`.
{ user, baseDir, path, grant }:
let
  # Every directory strictly between baseDir and path -- same
  # computation shape as mk-self-hosted-service.nix's own ancestorDirs,
  # generalized here since this helper has no dataDir concept of its own.
  # baseDir doesn't have to be an actual home directory -- just whatever
  # point above `path` is safe to start walking from (a home directory
  # for Immich's original hypothetical case, /run/media for
  # qBittorrent's real one).
  ancestorDirs =
    let
      baseParts = lib.splitString "/" baseDir;
      fullParts = lib.splitString "/" path;
      relParts = lib.sublist
        (builtins.length baseParts)
        (builtins.length fullParts - builtins.length baseParts - 1)
        fullParts;
    in
    lib.genList
      (i: baseDir + "/" + lib.concatStringsSep "/" (lib.sublist 0 (i + 1) relParts))
      (builtins.length relParts);
in
{
  # Wire into systemd.tmpfiles.rules when grant is true.
  tmpfilesRules =
    if grant then
      map (dir: "a+ ${dir} - - - - u:${user}:X") ancestorDirs
    else
      [ ];

  # Wire into a system.activationScripts entry when grant is false --
  # must actually run (tmpfilesRules alone won't clean up a previous
  # grant, `a+` is additive-only and removing the rule doesn't undo what
  # it already applied). Mutually exclusive with tmpfilesRules by
  # construction (only one of the two is ever non-empty for a given
  # `grant` value), so there's no ordering conflict between granting and
  # revoking within the same activation.
  revokeScript =
    if grant then
      ""
    else
      lib.concatMapStringsSep "\n"
        (dir: ''${pkgs.acl}/bin/setfacl -x u:${user} "${dir}" 2>/dev/null || true'')
        ancestorDirs;

  # Idempotent every-start form -- see this file's own top comment for
  # when to reach for this instead of tmpfilesRules/revokeScript.
  preStartScript =
    lib.concatMapStringsSep "\n"
      (dir:
        if grant then
          ''${pkgs.acl}/bin/setfacl -m u:${user}:X "${dir}" 2>/dev/null || true''
        else
          ''${pkgs.acl}/bin/setfacl -x u:${user} "${dir}" 2>/dev/null || true'')
      ancestorDirs;
}
