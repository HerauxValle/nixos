# &desc: "Sudo keyfile checker script -- no-mount read of the keyfile off the raw device (ext/FAT/NTFS/btrfs direct, others via mount fallback), SHA-256 compare."

{ pkgs, cfg }:

# Runs on EVERY "sudo" PAM auth attempt (interactive, smg/pmg background
# jobs, the sudo broker's own re-exec -- all of it, unscoped by design).
# Must fail fast, never hang: exit 1 for any missing/mismatched/erroring
# step just falls through to the normal password prompt (this rule is
# `sufficient`, not `required` -- see ../../sudo-keyfile.nix's own PAM rule).
#
# runtimeInputs wires the exact fs tools this needs directly into the
# script's PATH via the Nix closure -- no `command -v` presence checks
# needed anywhere, unlike an imperative install this would otherwise be
# a runtime concern.
#
# PAM's auth phase invokes this as the calling user (uid 1000 here), not
# root -- that's the whole point of an auth check, it can't already have
# the privilege it's deciding whether to grant. Reading a raw block
# device and root-owned secret files needs root though, so this alone
# would always fail (confirmed: debugged a live failure down to exactly
# this). Fixed in ../checker-stub/, not by weakening this to run
# unprivileged -- same setuid-root approach NixOS already uses for sudo
# and ping themselves.
#
# check.sh is a real standalone bash file (easier to lint/debug than an
# inline Nix string) -- @CONF_FILE@/@HASH_FILE@ are the only two dynamic
# bits, substituted in verbatim below.
pkgs.writeShellApplication {
  name = "sudo-keyfile-check";
  runtimeInputs = [
    pkgs.e2fsprogs # debugfs   -- ext2/3/4, no mount
    pkgs.mtools # mcopy     -- FAT/FAT32, no mount
    pkgs.ntfs3g # ntfscat   -- NTFS, no mount
    pkgs.btrfs-progs # restore   -- btrfs, no mount
    pkgs.util-linux # blkid, mount, umount
    pkgs.coreutils
  ];
  text = builtins.replaceStrings [ "@CONF_FILE@" "@HASH_FILE@" ] [
    cfg.confFile
    cfg.hashFile
  ] (builtins.readFile ./check.sh);
}
