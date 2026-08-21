#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DIR/lib/common.sh"

cmd_usage="rcon"
require_name "${1:-}"
name="$1"
shift || true

props="$(server_properties_path "$name")"
[ -f "$props" ] || { echo "no server.properties at $props -- has '$name' been started at least once?" >&2; exit 1; }

# Single source of truth is the rendered server.properties (regenerated
# from Nix's serverProperties on every start) -- no separate secrets file
# to keep in sync. See server.nix's own comment for why the real password
# is pinned in Nix in the first place.
enabled="$(grep -m1 '^enable-rcon=' "$props" | cut -d= -f2-)"
port="$(grep -m1 '^rcon\.port=' "$props" | cut -d= -f2-)"
pass="$(grep -m1 '^rcon\.password=' "$props" | cut -d= -f2-)"

if [ "$enabled" != "true" ] || [ -z "$port" ] || [ -z "$pass" ]; then
    echo "RCON isn't enabled for '$name' (enable-rcon/rcon.port/rcon.password missing from $props)" >&2
    exit 1
fi

# No args -> interactive shell (mcrcon's own default with no COMMANDS);
# args given -> one-shot, passed straight through.
exec mcrcon -H 127.0.0.1 -P "$port" -p "$pass" "$@"
