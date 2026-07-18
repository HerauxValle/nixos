#!/usr/bin/env bash
# &desc: "Venv listing tool -- shows all declared venvs, path, python version, package count, activation status, build state."
set -euo pipefail

source "$VENVCTL_LIBROOT/manage/manifest.sh"

data="$VENVCTL_DATA"

while IFS= read -r name; do
  path="$(jq -r --arg n "$name" '.[$n].resolvedPath' <<< "$data")"
  python_attr="$(jq -r --arg n "$name" '.[$n].python' <<< "$data")"
  n_pkgs="$(jq -r --arg n "$name" '.[$n].packages | length' <<< "$data")"
  on_entry="$(jq -r --arg n "$name" '.[$n].activation | length > 0' <<< "$data")"

  if [[ -x "$path/bin/python" ]]; then
    built="built"
  else
    built="NOT BUILT (run a rebuild)"
  fi

  printf "%-20s %-8s %-3s pkgs  entry=%-5s  %s\n" "$name" "$python_attr" "$n_pkgs" "$on_entry" "$built"
  printf "  %s\n" "$path"
done < <(jq -r 'keys[]' <<< "$data")
