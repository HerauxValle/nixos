# &desc: "Dedicated upgrade controller that pulls down the latest updates for floating PyPI strings and rewrites respective project lock targets."

#!/usr/bin/env bash
# Usage: update.sh <name|all>
# The counterpart to build.sh's deliberate refusal to touch "latest"
# packages -- this is the only place they actually get bumped.
set -euo pipefail

source "$VENVCTL_LIBROOT/manage/log.sh"
source "$VENVCTL_LIBROOT/manage/manifest.sh"

target="$1"
data="$VENVCTL_DATA"

update_one() {
  local name="$1" path packages_json
  path="$(jq -r --arg n "$name" '.[$n].resolvedPath // empty' <<< "$data")"
  packages_json="$(jq -c --arg n "$name" '.[$n].packages // {}' <<< "$data")"

  if [[ -z "$path" ]]; then
    log_error "unknown venv '$name' (not in current config)"
    return 1
  fi
  if [[ ! -x "$path/bin/pip" ]]; then
    log_error "venv '$name' not built yet -- run a rebuild first"
    return 1
  fi

  local any=0
  while IFS=$'\t' read -r pkg version; do
    [[ -z "$pkg" || "$version" != "latest" ]] && continue
    any=1
    log_debug "updating $pkg to latest"
    "$path/bin/pip" install --quiet --upgrade "$pkg" || { log_error "failed updating $pkg"; return 1; }
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$packages_json")

  [[ "$any" == 0 ]] && log_debug "'$name' has no floating packages, nothing to do"

  local want_lock
  want_lock="$(jq -r --arg n "$name" '.[$n].lockfile // false' <<< "$data")"
  if [[ "$want_lock" == "true" ]]; then
    source "$VENVCTL_LIBROOT/lock/lockfile.sh"
    lockfile_write "$name" "$path"
  fi

  log_result ok "$name"
}

if [[ "$target" == "all" ]]; then
  status=0
  while IFS= read -r name; do
    update_one "$name" || status=1
  done < <(jq -r 'keys[]' <<< "$data")
  exit "$status"
else
  update_one "$target"
fi
