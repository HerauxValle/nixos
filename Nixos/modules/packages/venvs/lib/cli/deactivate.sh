#!/usr/bin/env bash
# Usage: deactivate.sh [<currently active resolvedPath>]
# venvctl has no notion of "the active venv" on its own -- that state
# only ever exists as a shell variable inside whichever shell ran
# activate. The shim passes its own $VIRTUAL_ENV (if any) as $1 so the
# banner can name what's actually being unloaded, and list its packages,
# instead of a generic message. No arg, or a path that doesn't match
# anything declared, just falls back to the generic line with no list.
set -euo pipefail

: "${VENVCTL_LIBROOT:?VENVCTL_LIBROOT not set}"
# shellcheck source=../manage/log.sh
source "$VENVCTL_LIBROOT/manage/log.sh"

active_path="${1:-}"
entry=""

if [[ -n "$active_path" ]]; then
  entry="$(jq -c --arg p "$active_path" 'to_entries[] | select(.value.resolvedPath == $p) | .value' <<< "$VENVCTL_DATA" | head -n1)"
fi

if [[ -n "$entry" ]]; then
  name="$(jq -r --arg p "$active_path" '. as $d | $d | to_entries[] | select(.value.resolvedPath == $p) | .key' <<< "$VENVCTL_DATA" | head -n1)"
  _log_dot 32 "Unloading virtual environment $name" >&2
  while IFS=$'\t' read -r pkg ver; do
    _log_dot 32 "$pkg ($ver)" >&2
  done < <(jq -r '.packages // {} | to_entries[] | "\(.key)\t\(.value)"' <<< "$entry")
else
  _log_dot 32 "Unloading virtual environment" >&2
fi

echo "VIRTUAL_ENV="
