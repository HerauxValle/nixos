#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

cmd_usage="start"
parse_args "$@"
require_name "${ARGS[0]:-}"
name="${ARGS[0]}"
unit="$(unit_name "$name")"

if [ "$SILENT" -eq 1 ]; then
    run_silent "$CYAN" "starting $name" sudo systemctl start "$unit"
else
    run_with_spinner "$CYAN" "starting $name" sudo systemctl start "$unit"
fi
