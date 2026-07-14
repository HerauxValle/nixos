#!/usr/bin/env bash
# Usage: activate.sh <name|path>
# Prints, on success, exactly:
#   VIRTUAL_ENV=<resolved path>
#   PATH_PREPEND=<resolved path>/bin
# and nothing else on stdout -- shims parse this line-by-line. Anything
# diagnostic goes to stderr so it never corrupts the protocol. See
# docs/DECISIONS.md "Shim protocol" for why activation can't just mutate
# the calling shell directly.
set -euo pipefail

arg="$1"
data="$VENVCTL_DATA"

# Accept either a declared name, or a raw path (matched against every
# venv's resolvedPath) -- "path... just for good measure" per spec.
path="$(jq -r --arg n "$arg" '.[$n].resolvedPath // empty' <<< "$data")"

if [[ -z "$path" ]]; then
  path="$(jq -r --arg p "$arg" 'to_entries[] | select(.value.resolvedPath == $p) | .value.resolvedPath' <<< "$data" | head -n1)"
fi

if [[ -z "$path" ]]; then
  echo "venvctl: no declared venv matches '$arg'" >&2
  exit 1
fi

if [[ ! -x "$path/bin/python" ]]; then
  echo "venvctl: '$arg' resolves to $path but it isn't built yet -- run a rebuild first" >&2
  exit 1
fi

echo "VIRTUAL_ENV=$path"
echo "PATH_PREPEND=$path/bin"
