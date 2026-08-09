#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

cmd_usage="start"
require_name "${1:-}"
name="$1"
unit="$(unit_name "$name")"

run_with_spinner "starting $name ..." sudo systemctl start "$unit"
