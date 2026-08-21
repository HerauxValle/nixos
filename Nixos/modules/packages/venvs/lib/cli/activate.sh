#!/usr/bin/env bash
# &desc: "Venv activation protocol printer -- resolves by name/path, prints VIRTUAL_ENV/PATH_PREPEND for shim sourcing."
# Usage: activate.sh <name|path>
# Prints, on success, exactly:
#   VIRTUAL_ENV=<resolved path>
#   PATH_PREPEND=<resolved path>/bin
# and nothing else on stdout -- shims parse this line-by-line. Everything
# else (including the "Loading virtual environment" banner below) goes
# to stderr so it never corrupts the protocol. See docs/DECISIONS.md
# "Shim protocol" for why activation can't just mutate the calling shell
# directly.
set -euo pipefail

: "${VENVCTL_LIBROOT:?VENVCTL_LIBROOT not set}"
# shellcheck source=../manage/log.sh
source "$VENVCTL_LIBROOT/manage/log.sh" # reuse _log_dot for the banner below

arg="$1"
data="$VENVCTL_DATA"

# Accept either a declared name, or a raw path (matched against every
# venv's resolvedPath) -- "path... just for good measure" per spec.
# Resolved once as a single entry object so name/path/packages all come
# from the same match instead of three separate jq lookups.
entry="$(jq -c --arg n "$arg" '.[$n] // empty' <<< "$data")"
name="$arg"

if [[ -z "$entry" ]]; then
  match="$(jq -c --arg p "$arg" 'to_entries[] | select(.value.resolvedPath == $p)' <<< "$data" | head -n1)"
  if [[ -n "$match" ]]; then
    name="$(jq -r '.key' <<< "$match")"
    entry="$(jq -c '.value' <<< "$match")"
  fi
fi

if [[ -z "$entry" ]]; then
  echo "venvctl: no declared venv matches '$arg'" >&2
  exit 1
fi

path="$(jq -r '.resolvedPath' <<< "$entry")"

if [[ ! -x "$path/bin/python" ]]; then
  echo "venvctl: '$arg' resolves to $path but it isn't built yet -- run a rebuild first" >&2
  exit 1
fi

_log_dot 32 "Loading virtual environment" >&2
while IFS=$'\t' read -r pkg ver; do
  _log_dot 32 "$pkg ($ver)" >&2
done < <(jq -r '.packages // {} | to_entries[] | "\(.key)\t\(.value)"' <<< "$entry")

echo "VIRTUAL_ENV=$path"
echo "PATH_PREPEND=$path/bin"
