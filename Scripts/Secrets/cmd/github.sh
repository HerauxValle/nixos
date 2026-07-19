#!/usr/bin/env bash
# secrets github add/rem auth/sign -- (re)generate or remove one of your two
# personal GitHub SSH keys, independently of each other.
#
# auth: used for `git clone`/`push` over SSH -- Nixos/modules/security/
#       github-keys.nix deploys it to ~/.ssh/github-auth{,.pub} and wires
#       ~/.ssh/config to use it for github.com.
# sign: used for commit signing -- same module deploys it to
#       ~/.ssh/github-sign{,.pub} and points git's global gpg.format=ssh +
#       user.signingKey at the .pub half.
#
# Same shape as dotfiles.sh: generates the key locally, writes it to a
# root-owned file outside the checkout, never talks to any API. Registering
# the printed public key with GitHub (Settings -> SSH and GPG keys -> New
# SSH key, "Authentication Key" or "Signing Key" as appropriate) is a
# manual, one-time step you do yourself.
#
# `add <type>` OVERWRITES only that type's key -- the other type (if any)
# is never touched, generated, or deleted. The deployed ~/.ssh copy and any
# wiring only actually updates on the next `pacnix rebuild` (unlike
# dotfiles.sh's key, which needs no rebuild since nothing copies it
# anywhere -- this one does).
#
# `rem <type>` deletes only that type's root-owned key. The old public key
# keeps working on GitHub until you remove it there yourself -- this can't
# reach into GitHub's side of that trust relationship, only your side of it.
set -euo pipefail

SECRETS_DIR="/etc/nixos-secrets/github"
KEY_TYPE="ed25519"
HOSTNAME="$(hostname)"

usage() {
    echo "usage: secrets github <add|rem> <auth|sign>" >&2
    exit 1
}

action="${1:-}"
kind="${2:-}"

[[ "$action" != "add" && "$action" != "rem" ]] && usage
[[ "$kind" != "auth" && "$kind" != "sign" ]] && usage

KEY_FILE="$SECRETS_DIR/$kind"

if [[ "$action" == "rem" ]]; then
    if [[ ! -f "$KEY_FILE" ]]; then
        echo "no $kind key exists at $KEY_FILE -- nothing to remove."
        exit 0
    fi
    sudo rm -f "$KEY_FILE" "$KEY_FILE.pub"
    echo "Removed $kind key ($KEY_FILE)."
    echo "Run 'pacnix rebuild' to also remove the deployed ~/.ssh copy and its wiring."
    echo "Remember to delete the matching public key from GitHub yourself (Settings ->"
    echo "SSH and GPG keys) -- it keeps working there until you do."
    exit 0
fi

# action == add
if [[ -f "$KEY_FILE" ]]; then
    echo "A $kind key already exists at $KEY_FILE -- this will replace it."
    echo "The old public key keeps working on GitHub until you remove it there yourself."
fi

KEY_COMMENT="${HOSTNAME}-github-${kind}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ssh-keygen -q -t "$KEY_TYPE" -N "" -C "$KEY_COMMENT" -f "$tmp/key"

sudo install -d -m 700 -o root -g root "$SECRETS_DIR"
sudo install -m 600 -o root -g root "$tmp/key" "$KEY_FILE"
sudo install -m 644 -o root -g root "$tmp/key.pub" "$KEY_FILE.pub"

echo ""
echo "New $kind key written to $KEY_FILE (root:root, 600)."
echo "Run 'pacnix rebuild' to deploy it into ~/.ssh and finish wiring it up."
if [[ "$kind" == "auth" ]]; then
    echo "Then add this public key on GitHub: Settings -> SSH and GPG keys -> New SSH"
    echo "key -> Key type: Authentication Key."
else
    echo "Then add this public key on GitHub: Settings -> SSH and GPG keys -> New SSH"
    echo "key -> Key type: Signing Key."
fi
echo ""
sudo cat "$KEY_FILE.pub"
