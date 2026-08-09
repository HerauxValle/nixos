#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

cmd_usage="log"
require_name "${1:-}"
name="$1"
sock="$(sock_path "$name")"

[ -S "$sock" ] || { echo "no console socket at $sock -- is '$name' running? (mcli start $name)" >&2; exit 1; }

exec tmux -S "$sock" attach
