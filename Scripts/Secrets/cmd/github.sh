#!/usr/bin/env bash
# secrets github add/rem auth/sign/classic -- (re)generate or remove one of
# your personal GitHub credentials, independently of each other.
#
# auth: used for `git clone`/`push` over SSH -- Nixos/modules/security/
#       github-keys.nix deploys it to ~/.ssh/github-auth{,.pub} and wires
#       ~/.ssh/config to use it for github.com.
# sign: used for commit signing -- same module deploys it to
#       ~/.ssh/github-sign{,.pub} and points git's global gpg.format=ssh +
#       user.signingKey at the .pub half.
# classic: a GitHub classic personal access token (repo scope) -- pasted,
#          not generated. modules/packages/repos/repos.nix deploys it to
#          ~/.config/gitctl/classic-token. REQUIRED for `gitctl
#          release` -- it errors immediately if this is missing, since
#          `release` always means a real GitHub Release, same fields as
#          ~/Scripts/Python/gitpushall.py's create_github_release, just
#          no longer optional the way GITHUB_TOKEN was there. push never
#          touches this -- that stays plain SSH via the auth key above.
#
# Same shape as dotfiles.sh: writes to a root-owned file outside the
# checkout, never talks to any API itself. For auth/sign, registering the
# printed public key with GitHub (Settings -> SSH and GPG keys -> New SSH
# key, "Authentication Key" or "Signing Key" as appropriate) is a manual,
# one-time step you do yourself. For classic, generating the PAT itself
# (Settings -> Developer settings -> Personal access tokens -> Tokens
# (classic)) is the manual step -- this only stores what you paste.
#
# `add <kind>` OVERWRITES only that kind's credential -- the others (if
# any) are never touched, generated, or deleted. The deployed copy and
# any wiring only actually updates on the next `pacnix rebuild` (unlike
# dotfiles.sh's key, which needs no rebuild since nothing copies it
# anywhere -- these do).
#
# `rem <kind>` deletes only that kind's root-owned credential. For
# auth/sign, the old public key keeps working on GitHub until you remove
# it there yourself -- this can't reach into GitHub's side of that trust
# relationship, only your side of it. For classic, the PAT itself keeps
# working until revoked on GitHub the same way.
set -euo pipefail

SECRETS_DIR="/etc/nixos-secrets/github"
KEY_TYPE="ed25519"
HOSTNAME="$(hostname)"

usage() {
    echo "usage: secrets github <add|rem> <auth|sign|classic>" >&2
    exit 1
}

action="${1:-}"
kind="${2:-}"

[[ "$action" != "add" && "$action" != "rem" ]] && usage
[[ "$kind" != "auth" && "$kind" != "sign" && "$kind" != "classic" ]] && usage

KEY_FILE="$SECRETS_DIR/$kind"

if [[ "$action" == "rem" ]]; then
    if [[ ! -f "$KEY_FILE" ]]; then
        echo "no $kind credential exists at $KEY_FILE -- nothing to remove."
        exit 0
    fi
    sudo rm -f "$KEY_FILE" "$KEY_FILE.pub"
    echo "Removed $kind credential ($KEY_FILE)."
    if [[ "$kind" == "classic" ]]; then
        echo "Run 'pacnix rebuild' to also remove the deployed ~/.config/gitctl copy."
        echo "'gitctl release' will error until a new one is added -- it's required,"
        echo "not optional. Remember to revoke the token on GitHub yourself (Settings ->"
        echo "Developer settings -> Personal access tokens) -- it keeps working until you do."
    else
        echo "Run 'pacnix rebuild' to also remove the deployed ~/.ssh copy and its wiring."
        echo "Remember to delete the matching public key from GitHub yourself (Settings ->"
        echo "SSH and GPG keys) -- it keeps working there until you do."
    fi
    exit 0
fi

# action == add
if [[ -f "$KEY_FILE" ]]; then
    echo "A $kind credential already exists at $KEY_FILE -- this will replace it."
    if [[ "$kind" == "classic" ]]; then
        echo "The old token keeps working on GitHub until you revoke it there yourself."
    else
        echo "The old public key keeps working on GitHub until you remove it there yourself."
    fi
fi

if [[ "$kind" == "classic" ]]; then
    read -r -s -p "Paste your GitHub classic personal access token (repo scope): " token
    echo ""
    if [[ -z "$token" ]]; then
        echo "empty input -- nothing written." >&2
        exit 1
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    printf '%s' "$token" > "$tmp/classic"

    sudo install -d -m 700 -o root -g root "$SECRETS_DIR"
    sudo install -m 600 -o root -g root "$tmp/classic" "$KEY_FILE"

    echo ""
    echo "Token written to $KEY_FILE (root:root, 600)."
    echo "Run 'pacnix rebuild' to deploy it -- 'gitctl release' requires it and"
    echo "errors immediately if it's missing."
    exit 0
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
