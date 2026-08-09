#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

cmd_usage="fail"
parse_args "$@"
require_name "${ARGS[0]:-}"
name="${ARGS[0]}"
unit="$(unit_name "$name")"

# Unsticks a unit stuck in `failed` -- confirmed real cause on this repo
# (see config/software/programs/minecraft/servers/creative/package.nix):
# a slow multi-world ExecStartPost (world creation + a startup-race-safety
# sleep) blew past the old TimeoutStartSec, systemd killed it mid-run, and
# Restart=always then looped the unit through repeated failed boots.
# systemctl start alone refuses to touch a unit still in `failed` state --
# reset-failed clears that latch first, same fix either way regardless of
# what actually caused the failed state this time.
if ! systemctl is-failed --quiet "$unit"; then
    echo "'$name' isn't in a failed state (systemctl is-failed says so) -- nothing to fix." >&2
    echo "current status:" >&2
    systemctl status --no-pager "$unit" || true
    exit 1
fi

if [ "$SILENT" -eq 1 ]; then
    run_silent "$MAGENTA" "unsticking $name" sudo bash -c 'systemctl reset-failed "$1" && systemctl start "$1"' -- "$unit"
else
    run_with_spinner "$MAGENTA" "unsticking $name" sudo bash -c 'systemctl reset-failed "$1" && systemctl start "$1"' -- "$unit"
    systemctl status --no-pager "$unit"
fi
