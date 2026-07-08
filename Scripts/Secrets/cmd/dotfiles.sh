#!/usr/bin/env bash
# secrets dotfiles -- (re)generate the deploy key used to push the Dotfiles
# backup to its GitHub remote, any time.
#
# Same shape as passwd.sh: generates the secret locally, writes it to a
# root-owned file outside the checkout, and never talks to any API on its
# own. Registering the printed public key with GitHub (repo -> Settings ->
# Deploy keys, write access) is a manual, one-time step you do yourself --
# there's no way to automate that trust handoff without a far more
# powerful (and just as long-lived) GitHub token sitting on disk, which
# defeats the point of scoping this key to one repo in the first place.
#
# Nixos/modules/backup/dotfiles.nix reads this same file to push on every
# rebuild -- this script only ever (re)writes it, it never rebuilds or
# pushes anything itself.
#
# Running this OVERWRITES any existing key here -- the old public key stops
# working the moment you remove it from GitHub, but keeps working until
# then, so do that cleanup after confirming the new one is registered.
set -euo pipefail

SECRETS_DIR="/etc/nixos-secrets/github"
KEY_FILE="$SECRETS_DIR/dotfiles-backup"
KEY_TYPE="ed25519"

# Derived relative to this script's own location (Scripts/Secrets/cmd/ is
# three levels below the Dotfiles root) rather than a separately hardcoded
# name -- stays correct even if the checkout is ever renamed, and matches
# Nixos/modules/backup/dotfiles.nix's own keyComment derivation.
DOTFILES_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../.." && pwd)"
KEY_COMMENT="$(basename "$DOTFILES_ROOT")-backup"

if [ -f "$KEY_FILE" ]; then
    echo "A deploy key already exists at $KEY_FILE -- this will replace it."
    echo "The old public key keeps working on GitHub until you remove it there yourself."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ssh-keygen -q -t "$KEY_TYPE" -N "" -C "$KEY_COMMENT" -f "$tmp/key"

sudo install -d -m 700 -o root -g root "$SECRETS_DIR"
sudo install -m 600 -o root -g root "$tmp/key" "$KEY_FILE"
sudo install -m 644 -o root -g root "$tmp/key.pub" "$KEY_FILE.pub"

echo ""
echo "New deploy key written to $KEY_FILE (root:root, 600)."
echo "Add this public key to the Dotfiles repo on GitHub (Settings -> Deploy keys ->"
echo "Add deploy key, tick 'Allow write access'), then it's usable immediately --"
echo "no rebuild needed for the key itself, only if you also changed remoteUrl/branch"
echo "in Nixos/modules/backup/dotfiles.nix:"
echo ""
sudo cat "$KEY_FILE.pub"
