#!/usr/bin/env bash
# Usage: build.sh <name> <resolvedPath> <pythonAttr> <packagesJson> <lockfile:true|false>
# Called once per declared venv from sync.sh. Idempotent: safe to run on
# every rebuild even if nothing changed.
set -euo pipefail

# shellcheck source=./log.sh
source "$VENVCTL_LIBROOT/manage/log.sh"
# shellcheck source=./manifest.sh
source "$VENVCTL_LIBROOT/manage/manifest.sh"

name="$1" path="$2" python_attr="$3" packages_json="$4" want_lock="$5"

log_debug "building '$name' at $path (python: $python_attr)"

mkdir -p "$(dirname "$path")"

if [[ ! -x "$path/bin/python" ]]; then
  log_debug "no existing interpreter found, creating venv"
  # $python_attr is a nixpkgs attribute name resolved by the caller into
  # an actual interpreter on PATH (via runtimeInputs on venvctl / the
  # activation script's own PATH) -- build.sh itself just shells out to
  # whatever `python3` resolves to, since resolving the attr name to a
  # store path from bash isn't build.sh's job.
  python3 -m venv "$path"
fi

prev_packages="$(manifest_get_packages "$name")"

# Pinned packages: install/reinstall if version differs from last run.
# Floating ("latest") packages: install only if genuinely missing --
# never upgraded here, only by an explicit `venvctl update`.
while IFS=$'\t' read -r pkg version; do
  [[ -z "$pkg" ]] && continue
  prev_version="$(jq -r --arg p "$pkg" '.[$p] // empty' <<< "$prev_packages")"

  if [[ "$version" == "latest" ]]; then
    if ! "$path/bin/pip" show "$pkg" >/dev/null 2>&1; then
      log_debug "installing $pkg (latest, first install)"
      "$path/bin/pip" install --quiet "$pkg" || { log_error "failed installing $pkg"; exit 1; }
    else
      log_debug "$pkg already present, leaving 'latest' alone (use: venvctl update)"
    fi
  elif [[ "$version" != "$prev_version" ]]; then
    log_debug "installing $pkg==$version (was: ${prev_version:-none})"
    "$path/bin/pip" install --quiet "$pkg==$version" || { log_error "failed installing $pkg==$version"; exit 1; }
  else
    log_debug "$pkg==$version unchanged"
  fi
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' <<< "$packages_json")

manifest_write_entry "$name" "$path" "$packages_json"

if [[ "$want_lock" == "true" ]]; then
  # shellcheck source=../lock/lockfile.sh
  source "$VENVCTL_LIBROOT/lock/lockfile.sh"
  lockfile_write "$name" "$path"
fi

log_result ok "$name"
