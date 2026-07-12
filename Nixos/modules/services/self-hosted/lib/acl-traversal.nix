{ lib, pkgs }:

# STATUS: real, working primitives (both individually verified against a
# live filesystem this session -- see the exact commands in each comment
# below), but this Nix function itself has NO current caller anywhere in
# this repo. Written ahead of a confirmed need, per direct instruction,
# specifically so the next service that hits this problem for real has a
# ready, already-tested-at-the-primitive-level place to start instead of
# reinventing it -- NOT wired into self-hosted.nix's own re-export yet,
# and not exercised end-to-end as a Nix module (no rebuild has ever
# actually applied this function's output). Wire it in and exercise it
# for real the same way every other piece of this framework was verified
# (docs/adding-a-service.md's "verify before calling it done") before
# trusting it blind.
#
# The problem this solves: a service that runs as a dedicated,
# non-human system user (not `config.vars.username`) but needs to reach
# one specific path nested inside a human user's home directory. Home
# directories on this machine are 0700 (`/home/<user>`, confirmed) --
# completely opaque to any unrelated system account, regardless of how
# permissively the target leaf path itself is chowned. Every other
# service in this framework sidesteps this entirely by running its own
# live process `User = config.vars.username;` (the human user, who
# obviously already owns their own home tree) -- this helper is only
# for the case where that's not true (a wrapped native module that
# insists on its own dedicated system user, the way services.immich
# does).
#
# Immich itself does NOT need this (see immich/immich.nix's own
# comment): `ProtectHome = "tmpfs"` + `BindPaths` on the exact paths
# needed turned out to be sufficient on its own -- systemd builds the
# intermediate path structure for BindPaths inside its own synthetic,
# root-owned tmpfs, never actually walking the real (0700) home
# directory at all, so the traversal problem this helper solves never
# actually applied once that fix was in place. This helper stays for a
# genuinely different, currently-hypothetical case: a service that
# reads/writes a home-rooted path *without* systemd-level sandboxing
# namespacing it away first (no ProtectHome/BindPaths involved at all --
# e.g. a plain preStart script, or a service that can't use
# ProtectHome=tmpfs for some other reason), where the dedicated user's
# own real, unsandboxed traversal permission genuinely is the only thing
# standing in the way.
#
# grant = true: an execute-only ("X" -- POSIX ACL conditional execute:
# only applies to directories or files already executable for someone,
# never silently grants execute on a plain file, see acl(5)) entry for
# `user` on every ancestor directory between `homeDirectory` and `path`.
# Verified idempotent by real repetition (ran three times in a row against
# a live test directory, `getfacl` showed exactly one entry, not three):
#
#   systemd-tmpfiles --create - <<< "a+ <dir> - - - - u:<user>:X"
#
# grant = false: actively *removes* that entry, not just omits granting
# it -- necessary for "properly update on reload" (a later rebuild that
# flips this to false must not leave a stale grant behind). systemd-
# tmpfiles' own "replace" line type (`a`, no `+`) was tried first and
# confirmed *unsafe* for this: it requires a non-empty argument, and
# supplying anything other than the exact real base ACL entries (which
# Nix can't know at eval time -- real, live filesystem state) silently
# corrupted the reported group permission bits in a real test (a
# `m::rwx` mask placeholder widened the effective group permission from
# r-x to rwx, confirmed via `stat`/`getfacl` before and after). `setfacl
# -x` removes only the one named entry and nothing else, confirmed by
# direct testing not to touch the mask or any other bit, and confirmed
# idempotent (exit 0 even when the entry was never granted in the first
# place, safe to run unconditionally every activation):
#
#   setfacl -x u:<user> <dir>
{ user, homeDirectory, path, grant }:
let
  # Every directory strictly between homeDirectory and path -- same
  # computation shape as mk-self-hosted-service.nix's own ancestorDirs,
  # generalized here since this helper has no dataDir concept of its own.
  ancestorDirs =
    let
      baseParts = lib.splitString "/" homeDirectory;
      fullParts = lib.splitString "/" path;
      relParts = lib.sublist
        (builtins.length baseParts)
        (builtins.length fullParts - builtins.length baseParts - 1)
        fullParts;
    in
    lib.genList
      (i: homeDirectory + "/" + lib.concatStringsSep "/" (lib.sublist 0 (i + 1) relParts))
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
}
