# &desc: "Targeted venv uninstallation engine that safely tears down old runtime environments matching untracked manifest keys."

#!/usr/bin/env bash
# Usage: remove.sh <name>
# Called by sync.sh for manifest entries with no matching declared venv.
# Deliberately trusts the manifest's recorded path over anything else --
# if the path was hand-edited outside nix, this is exactly the escape
# hatch that stops us rm -rf'ing the wrong directory.
set -euo pipefail

source "$VENVCTL_LIBROOT/manage/log.sh"
source "$VENVCTL_LIBROOT/manage/manifest.sh"

name="$1"
path="$(manifest_get_path "$name")"

if [[ -z "$path" ]]; then
  log_error "remove.sh: '$name' has no manifest entry, nothing to do"
  exit 0
fi

if [[ -d "$path" ]]; then
  log_debug "removing venv '$name' at $path"
  rm -rf -- "$path"
else
  log_debug "'$name' manifest path $path already gone, just cleaning manifest"
fi

manifest_remove_entry "$name"
log_result ok "$name (removed)"
