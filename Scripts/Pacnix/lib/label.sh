#!/usr/bin/env bash
# Computes the generation label: the normal auto-generated one (date/
# version based), with "-<custom>" appended only if a custom label was
# actually given. NIXOS_LABEL only allows [a-zA-Z0-9:_.-] (no spaces),
# hence "-" not " - " as the separator.
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/common.sh"

custom="${1:-}"
default_label=$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.system.nixos.label" 2>/dev/null)

if [ -n "$custom" ]; then
    echo "${default_label}-${custom}"
else
    echo "$default_label"
fi
