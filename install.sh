#!/usr/bin/env bash
# install.sh -- bootstrap a system onto this checkout:
#   1. Symlinks /etc/nixos -> this checkout, if it isn't already. That's
#      what actually matters: Scripts/Pacnix/lib/common.sh hardcodes
#      FLAKE="/etc/nixos", so `pacnix rebuild` (and a plain `nixos-rebuild
#      switch --flake /etc/nixos#herauxvalle`) both resolve through this
#      symlink, not a path into $HOME directly.
#   2. Runs Scripts/Secrets/secrets.sh passwd once, for the initial
#      password -- that script is the reusable one (also wired up as the
#      `secrets` command via scripts.nix) for whenever you actually want to
#      change it later; this is just step 2 of first-time setup, not
#      duplicated here.
#
# Safe to re-run: skips the symlink step if already correct.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# ── /etc/nixos symlink ───────────────────────────────────────────────────────
if [ -L /etc/nixos ] && [ "$(readlink -f /etc/nixos)" = "$SCRIPT_DIR" ]; then
    echo "/etc/nixos already -> $SCRIPT_DIR"
elif [ -e /etc/nixos ]; then
    echo "/etc/nixos exists and isn't already this checkout -- not touching it." >&2
    echo "Move or remove it yourself, then re-run this script, if you want it linked here." >&2
    exit 1
else
    sudo ln -s "$SCRIPT_DIR" /etc/nixos
    echo "Linked: /etc/nixos -> $SCRIPT_DIR"
fi

bash "$SCRIPT_DIR/Scripts/Secrets/secrets.sh" passwd
