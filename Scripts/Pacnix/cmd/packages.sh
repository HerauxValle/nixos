#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
target="$DIR/../../../Nixos/modules/packages/installed.nix"

exec "${EDITOR:-nano}" "$target"
