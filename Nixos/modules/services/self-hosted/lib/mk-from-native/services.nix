{ lib, pkgs }:

# The one real "wrap something nixpkgs already provides maturely, apply
# this framework's own thin conventions on top" builder -- see
# ./README.md for the other four categories (programs-root, programs-
# user, pkgs, nur) this sits alongside, all unimplemented until a real
# caller needs one.
#
# Deliberately thin, same spirit as mkSelfHostedService but for a
# service whose systemd units are already fully built by an upstream
# NixOS module (services.<name>): gate the wrapped module's own config on
# `enabled` (so a disabled service is genuinely absent, not just inert),
# and merge in the same requireMounts preStart check every
# mkSelfHostedService unit already gets. Everything else -- the real
# services.<name>.* field mapping, host/port, extra systemd overrides --
# is service-specific logic the caller writes directly into extraConfig,
# never inferred here (see docs/conventions.md's "data and logic never
# share a file" -- extraConfig IS that logic, owned by the one service
# that needs it, not abstracted from a single example).
{ enabled ? false
, requireMounts ? [ ]
  # Names of systemd.services.<name> units the wrapped module already
  # defines that requireMounts should actually gate, as a preStart check
  # (NixOS's own `preStart` option is `types.lines` -- mergeable, so this
  # concatenates cleanly onto whatever preStart the wrapped module itself
  # already sets, never replaces it). Not necessarily every unit the
  # wrapped module creates -- e.g. Immich's immich-machine-learning
  # sidecar never touches mediaLocation, so it has no reason to wait on
  # the same mount immich-server does. Caller decides which units
  # genuinely need it.
, mountCheckUnits ? [ ]
, extraConfig ? { }
}:
let
  mountCheck = lib.concatMapStringsSep "\n"
    (path: ''
      mountpoint -q "${path}" || {
        echo "self-hosted: ${path} is not mounted" >&2
        exit 1
      }
    '')
    requireMounts;
in
lib.mkMerge [
  (lib.mkIf enabled extraConfig)
  (lib.mkIf (enabled && requireMounts != [ ] && mountCheckUnits != [ ]) {
    systemd.services = lib.genAttrs mountCheckUnits (_: {
      preStart = mountCheck;
      # mountpoint isn't on a bare systemd unit's PATH by default --
      # same real failure mkSelfHostedService's own requireMounts
      # handling already found and fixed for the from-scratch case.
      path = [ pkgs.util-linux ];
    });
  })
]
