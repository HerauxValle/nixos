#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

label=""
impure=""
while [ $# -gt 0 ]; do
    case "$1" in
        --label) label="$2"; shift 2 ;;
        --impure) impure="--impure"; shift ;;
        *) shift ;;
    esac
done

if [ -n "$label" ]; then
    export NIXOS_LABEL
    NIXOS_LABEL="$(bash "$DIR/../lib/label.sh" "$label")"
fi

sudo nixos-rebuild switch --flake "$FLAKE#$HOST" $impure

# Reuses the real reload.sh directly rather than duplicating its logic --
# only runs if the rebuild above actually succeeded (set -e already stops
# the script on failure before reaching here).
bash "$DIR/reload.sh"
