#!/usr/bin/env bash
# Entry point invoked directly by venv.nix's home.activation block.
# Expects VENVCTL_LIBROOT, VENVCTL_DATA, VENVCTL_MANIFEST, VENVCTL_LOGLEVEL
# already exported by the caller (see venv.nix).
set -euo pipefail

source "$VENVCTL_LIBROOT/manage/log.sh"
source "$VENVCTL_LIBROOT/manage/manifest.sh"

manifest_ensure

declared_names="$(jq -r 'keys | join(" ")' <<< "$VENVCTL_DATA")"

# Build/verify every declared venv first, so a failure removing an old
# one never leaves you without the venvs you actually still want.
status=0
while IFS= read -r name; do
  path="$(jq -r --arg n "$name" '.[$n].resolvedPath' <<< "$VENVCTL_DATA")"
  python_attr="$(jq -r --arg n "$name" '.[$n].python' <<< "$VENVCTL_DATA")"
  packages_json="$(jq -c --arg n "$name" '.[$n].packages' <<< "$VENVCTL_DATA")"
  lockfile="$(jq -r --arg n "$name" '.[$n].lockfile' <<< "$VENVCTL_DATA")"

  bash "$VENVCTL_LIBROOT/manage/build.sh" "$name" "$path" "$python_attr" "$packages_json" "$lockfile" || status=1
done < <(jq -r 'keys[]' <<< "$VENVCTL_DATA")

# Then prune manifest entries with no matching declaration.
while IFS= read -r stale; do
  [[ -z "$stale" ]] && continue
  bash "$VENVCTL_LIBROOT/manage/remove.sh" "$stale" || status=1
done < <(manifest_names_not_in "$declared_names")

exit "$status"
