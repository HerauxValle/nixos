# &desc: "Venv creation utility that boots environments, handles floating versus explicit package specifications, and triggers downstream lock writes."

#!/usr/bin/env bash
# Usage: build.sh <name> <resolvedPath> <pythonBin> <packagesJson> <lockfile:true|false>
# <pythonBin> is a resolved store path (e.g. /nix/store/.../bin/python3),
# not a bare nixpkgs attr name -- resolution happens in venv.nix at eval
# time, since build.sh has no reliable PATH to find any interpreter on
# when it's invoked directly from a home-manager activation script
# rather than through venvctl.
set -euo pipefail

# shellcheck source=./log.sh
source "$VENVCTL_LIBROOT/manage/log.sh"
# shellcheck source=./manifest.sh
source "$VENVCTL_LIBROOT/manage/manifest.sh"

name="$1" path="$2" python_bin="$3" packages_json="$4" want_lock="$5"

log_debug "building '$name' at $path (interpreter: $python_bin)"

mkdir -p "$(dirname "$path")"

if [[ ! -x "$python_bin" ]]; then
  log_error "interpreter '$python_bin' does not exist or isn't executable"
  exit 1
fi

if [[ ! -x "$path/bin/python" ]]; then
  log_debug "no existing interpreter found, creating venv"
  "$python_bin" -m venv "$path"
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
