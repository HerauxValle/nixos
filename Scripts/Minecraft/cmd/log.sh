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

# sudo, not a plain attach: nix-minecraft's tmux hook (server-access -aw
# nobody, see the PrivateUsers comment in servers/creative/package.nix)
# only grants access to root/the namespace-mapped "nobody" identity --
# any other real user, including this one, gets "access not allowed"
# confirmed live even with the right group membership and socket perms.
exec sudo tmux -S "$sock" attach
