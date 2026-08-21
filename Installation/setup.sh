#!/usr/bin/env bash
# &desc: "OS setup step (formerly the repo-root install.sh) -- symlinks /etc/nixos, regenerates hardware-configuration.nix, seeds the initial password. Run via '../install.sh --setup', not directly."
#
# setup.sh -- bootstrap a system onto this checkout:
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
#
# On a genuinely fresh install (blank disk), run ../install.sh --format
# first -- this step assumes a partitioned, formatted, booted system.
set -euo pipefail

# One level up from this script's own directory (Installation/) -- the
# repo root, same value the old repo-root install.sh computed for
# itself before it moved here.
REPO_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"

# ── /etc/nixos symlink ───────────────────────────────────────────────────────
if [ -L /etc/nixos ] && [ "$(readlink -f /etc/nixos)" = "$REPO_ROOT" ]; then
    echo "/etc/nixos already -> $REPO_ROOT"
elif [ -e /etc/nixos ]; then
    echo "/etc/nixos exists and isn't already this checkout -- not touching it." >&2
    echo "Move or remove it yourself, then re-run this script, if you want it linked here." >&2
    exit 1
else
    sudo ln -s "$REPO_ROOT" /etc/nixos
    echo "Linked: /etc/nixos -> $REPO_ROOT"
fi

# ── hardware-configuration.nix ──────────────────────────────────────────────
sudo nixos-generate-config --dir "$REPO_ROOT/Nixos"
echo "Regenerated: $REPO_ROOT/Nixos/hardware-configuration.nix"

bash "$REPO_ROOT/Scripts/Secrets/secrets.sh" passwd
