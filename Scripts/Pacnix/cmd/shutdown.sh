#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Same rebuild rebuild.sh already does (including its own reload.sh call)
# -- reused directly, not duplicated, so --label/--impure and the actual
# switch logic can never drift between `pacnix rebuild` and this one.
# set -e above means a failed rebuild never reaches the shutdown below.
bash "$DIR/rebuild.sh" "$@"

echo "rebuild succeeded -- shutting down now"
sudo systemctl poweroff
