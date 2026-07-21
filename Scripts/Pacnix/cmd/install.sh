#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

# Run from inside the booted live-install ISO (see cmd/release.sh)
# against the flake embedded at /dotfiles (Nixos/iso.nix's
# isoImage.contents). Orchestrates the existing, already-VM-verified
# Installation/format.sh + nixos-install in sequence -- every existing
# confirmation in format.sh (pick disk, retype resolved path, type
# WIPE) stays exactly as it is; this is one entry point over two manual
# steps, not a new destructive path.
#
# Needs $DISKO_ROOT_KEYFILE already exported, same as running
# format.sh directly -- this script doesn't touch, generate, or ask
# for it. format.sh itself errors clearly if it's unset.

DOTFILES=/dotfiles
if [ ! -d "$DOTFILES" ]; then
    echo "$DOTFILES not found -- this only runs inside the booted live-install ISO." >&2
    exit 1
fi

bash "$DOTFILES/install.sh" --format

mapfile -t resolved < <(cd "$DOTFILES" && resolve_flake_attrs .)
attr="${resolved[0]}"

echo ""
echo "Installing nixosConfigurations.$attr onto /mnt..."
nixos-install --root /mnt --flake "$DOTFILES#$attr"

echo ""
echo "Install complete. Reboot into the new system, then run"
echo "./install.sh --setup from $DOTFILES (or wherever it ends up"
echo "checked out/linked to as /etc/nixos on the installed system)."
