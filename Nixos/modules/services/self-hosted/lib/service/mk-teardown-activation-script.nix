# &desc: "Service teardown activation builder -- removes dataDir/storage/venvDir on enabled=false, scoped via teardownPaths option."

{ lib }:

# Runs the "flip to disabled -> tear down what's reconcilable" half of
# the enabled/disabled lifecycle. Can't live in preStart -- when
# `enabled = false`, mkSelfHostedService's own live-service block
# (including the systemd unit preStart would hook into) doesn't exist at
# all. `system.activationScripts` is the one place that still runs on
# every `nixos-rebuild switch` regardless of whether this service's own
# systemd unit exists this generation.
#
# teardownPaths controls the blast radius, not a hardcoded "everything
# except storage" rule:
#   - `[ ]` (default): remove everything directly under dataDir except
#     what a `storage` entry's `src` covers. Safe for services whose
#     dataDir genuinely holds nothing else (Ollama, OpenWebUI, Stash --
#     confirmed by their own dataDir doc comments, not assumed).
#   - non-empty: remove *only* those paths, storage or not. Required
#     for ComfyUI, whose dataDir also holds output/temp/input -- real
#     generated/uploaded content, never covered by any storage entry,
#     that a blanket "everything but storage" sweep would destroy. This
#     is exactly the failure mode that killed the old two-tier
#     mkUninstallScript entirely -- see docs/architecture.md.
#
# venvDir (if any) always gets wiped too -- it's already outside
# dataDir/storage entirely, nothing to scope.
#
# Idempotent (rm -rf on an already-missing path is a no-op) -- safe to
# run on every switch for as long as `enabled` stays false, not just
# the one that first flips it.
{ name
, enabled
, dataDir ? null
, storage ? [ ]
, teardownPaths ? [ ]
, venvDir ? null
}:
lib.mkIf (!enabled) {
  system.activationScripts."self-hosted-${name}-teardown" = {
    text =
      let
        protectedNames = map (s: s.src) storage;
        skipCase =
          if protectedNames == [ ] then "" else ''
            case "$base" in
              ${lib.concatMapStringsSep "|" lib.escapeShellArg protectedNames}) continue ;;
            esac
          '';
        dataDirTeardown =
          if dataDir == null then ""
          else if teardownPaths != [ ] then
            lib.concatMapStringsSep "\n" (p: ''rm -rf "${dataDir}/${p}"'') teardownPaths
          else ''
            if [ -d "${dataDir}" ]; then
              for entry in "${dataDir}"/*; do
                [ -e "$entry" ] || continue
                base="$(basename "$entry")"
                ${skipCase}
                rm -rf "$entry"
              done
            fi
          '';
      in
      ''
        set -euo pipefail
        shopt -s dotglob nullglob
        ${dataDirTeardown}
        ${lib.optionalString (venvDir != null) ''rm -rf "${venvDir}"''}
        echo "self-hosted-${name}: disabled -- removed reconcilable install artifacts (storage-backed data untouched)."
      '';
  };
}
