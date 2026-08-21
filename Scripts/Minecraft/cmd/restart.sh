#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

cmd_usage="restart"
parse_args "$@"
require_name "${ARGS[0]:-}"
name="${ARGS[0]}"
unit="$(unit_name "$name")"

if [ "$SILENT" -eq 1 ]; then
    run_silent "$YELLOW" "restarting $name" sudo systemctl restart "$unit"
else
    run_with_spinner "$YELLOW" "restarting $name" sudo systemctl restart "$unit"
fi
