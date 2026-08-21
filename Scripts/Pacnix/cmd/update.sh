#!/usr/bin/env bash
# &desc: "pacnix update -- nix flake update against $FLAKE, optionally scoped to one input."
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

if [ $# -gt 0 ]; then
    nix flake update "$@" --flake "$FLAKE"
else
    nix flake update --flake "$FLAKE"
fi
