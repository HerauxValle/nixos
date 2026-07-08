#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"
nix build --no-link --print-out-paths "$FLAKE#nixosConfigurations.$HOST.config.system.build.toplevel"
