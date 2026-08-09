#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

cmd_usage="fail"
require_name "${1:-}"
name="$1"
unit="$(unit_name "$name")"

# Same unstick-a-failed-unit fix as `mcli fail` (Scripts/Minecraft) --
# systemctl start alone refuses to touch a unit still latched `failed`,
# reset-failed clears that latch first regardless of what actually caused
# it this time.
if ! systemctl is-failed --quiet "$unit"; then
    echo "'$name' isn't in a failed state (systemctl is-failed says so) -- nothing to fix." >&2
    echo "current status:" >&2
    systemctl status --no-pager "$unit" || true
    exit 1
fi

run_with_spinner "$MAGENTA" "unsticking $name" sudo bash -c 'systemctl reset-failed "$1" && systemctl start "$1"' -- "$unit"
systemctl status --no-pager "$unit"
