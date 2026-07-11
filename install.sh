#!/usr/bin/env bash
# install.sh -- bootstrap a system onto this checkout:
#   1. Symlinks /etc/nixos -> this checkout, if it isn't already. That's
#      what actually matters: Scripts/Pacnix/lib/common.sh hardcodes
#      FLAKE="/etc/nixos", so `pacnix rebuild` (and a plain `nixos-rebuild
#      switch --flake /etc/nixos#herauxvalle`) both resolve through this
#      symlink, not a path into $HOME directly.
#   2. Regenerates Nixos/hardware-configuration.nix for whatever machine
#      this actually is -- the checked-in copy only ever matches the
#      machine it was generated on. Always overwritten unconditionally
#      (that's nixos-generate-config's own behavior for this file, not a
#      flag here); Nixos/configuration.nix is left alone either way, since
#      it already exists and is hand-authored.
#   3. Runs Scripts/Secrets/secrets.sh passwd once, for the initial
#      password -- that script is the reusable one (also wired up as the
#      `secrets` command via scripts.nix) for whenever you actually want to
#      change it later; this is just step 3 of first-time setup, not
#      duplicated here.
#
# Safe to re-run: skips the symlink step if already correct, and
# regenerating hardware-configuration.nix again is harmless.
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

# ── hardware-configuration.nix ──────────────────────────────────────────────
sudo nixos-generate-config --dir "$SCRIPT_DIR/Nixos"
echo "Regenerated: $SCRIPT_DIR/Nixos/hardware-configuration.nix"

bash "$SCRIPT_DIR/Scripts/Secrets/secrets.sh" passwd
