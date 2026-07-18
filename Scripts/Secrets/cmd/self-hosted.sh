#!/usr/bin/env bash
# secrets self-hosted <name> -- (re)set env-var secrets for a self-hosted
# service, any time.
#
# Prompts for KEY=VALUE pairs (masked value input, same feedback style as
# `secrets passwd`), writes them to a root-owned file that systemd's
# EnvironmentFile= reads directly at service start --
# config.vars.services.selfHosted.<name>.environmentFile in
# Nixos/modules/services/self-hosted/self-hosted.nix. Nix only ever knows
# the *path*, same hashedPasswordFile pattern `secrets passwd` uses for
# the login password, just for arbitrary tokens instead of one hash, and
# generic over service name -- adding a service that needs secrets later
# touches nothing here.
#
# A service restart (not a rebuild) is what deploys a changed value --
# this only writes the file.
set -euo pipefail

name="${1:-}"
if [ -z "$name" ]; then
    echo "usage: secrets self-hosted <service-name>" >&2
    exit 1
fi

SECRETS_FILE="/etc/nixos-secrets/self-hosted/${name}/tokens.env"

_read_value() {
    local prompt="$1" val="" char
    printf '%s' "$prompt" >&2
    while IFS= read -r -s -n 1 char; do
        [ -z "$char" ] && break   # Enter
        if [ "$char" = $'\x7f' ]; then   # Backspace
            if [ -n "$val" ]; then
                val="${val%?}"
                printf '\b \b' >&2
            fi
        else
            val+="$char"
            printf '*' >&2
        fi
    done
    printf '\n' >&2
    printf '%s' "$val"
}

# Existing keys keep their value unless explicitly re-entered below --
# this is an edit/add operation, not an overwrite-everything one.
declare -A entries
if sudo test -f "$SECRETS_FILE"; then
    while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        entries["$k"]="$v"
    done < <(sudo cat "$SECRETS_FILE")
    echo "Existing keys for '$name': ${!entries[*]}" >&2
fi

echo "Setting secrets for '$name' -> $SECRETS_FILE" >&2
echo "(existing keys keep their value unless re-entered)" >&2
while true; do
    printf 'Key (blank to finish): ' >&2
    read -r key
    [ -z "$key" ] && break
    val="$(_read_value "Value for $key: ")"
    entries["$key"]="$val"
done

# bash quirk: an associative array that's never had an element assigned
# reads as unbound under `set -u`, even though it was `declare -A`'d --
# hit this for real (blank first prompt = 0 keys entered = crash here).
set +u
count="${#entries[@]}"
set -u
if [ "$count" -eq 0 ]; then
    echo "No keys, nothing written." >&2
    exit 0
fi

sudo install -d -m 700 -o root -g root "$(dirname "$SECRETS_FILE")"
{
    for k in "${!entries[@]}"; do
        printf '%s=%s\n' "$k" "${entries[$k]}"
    done
} | sudo tee "$SECRETS_FILE" > /dev/null
sudo chown root:root "$SECRETS_FILE"
sudo chmod 600 "$SECRETS_FILE"
unset entries

echo ""
echo "Wrote $count key(s) to $SECRETS_FILE (root:root, 600)."
echo "Run: sudo systemctl restart self-hosted-${name}"
