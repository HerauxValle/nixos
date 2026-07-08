#!/usr/bin/env bash
# secrets passwd — (re)set the account password's hash file, any time.
#
# Prompts for a password (confirmed twice, asterisk feedback per keystroke
# instead of either a blank/invisible read or echoing it in plain text),
# hashes it, and writes it to a root-owned file for
# users.users.herauxvalle.hashedPasswordFile in Nixos/modules/system/users.nix.
#
# hashedPasswordFile (a file reference, read by the activation script at
# rebuild time) instead of hashedPassword (a literal hash string baked
# directly into the Nix config) keeps the hash out of the world-readable
# /nix/store. That file deliberately lives outside /etc/nixos — /etc/nixos
# IS the Dotfiles checkout (symlinked there by install.sh), so anything
# placed inside it would sit inside the checkout itself, at real risk of
# ending up git-tracked/shared. /etc/nixos-secrets/ is a sibling directory
# instead, never part of the checkout.
#
# A rebuild is still what actually deploys the new hash to the running
# system — this only writes the file.
set -euo pipefail

HASH_FILE="/etc/nixos-secrets/herauxvalle-password.hash"

_read_password() {
    local prompt="$1" pass="" char
    printf '%s' "$prompt" >&2
    while IFS= read -r -s -n 1 char; do
        [ -z "$char" ] && break   # Enter
        if [ "$char" = $'\x7f' ]; then   # Backspace
            if [ -n "$pass" ]; then
                pass="${pass%?}"
                printf '\b \b' >&2
            fi
        else
            pass+="$char"
            printf '*' >&2
        fi
    done
    printf '\n' >&2
    printf '%s' "$pass"
}

pass1="$(_read_password "New password: ")"
pass2="$(_read_password "Confirm password: ")"

if [ -z "$pass1" ]; then
    echo "Password cannot be empty, aborting." >&2
    exit 1
fi
if [ "$pass1" != "$pass2" ]; then
    echo "Passwords do not match, aborting." >&2
    exit 1
fi

# -s reads the password from stdin (fd 0) instead of it ever being a CLI
# argument, which would otherwise be briefly visible to other processes/
# users via /proc/<pid>/cmdline while mkpasswd runs.
#
# mkpasswd is declared in installed.nix, so it's normally already on $PATH
# — except on the very first run of install.sh, before installed.nix has
# ever been deployed (nothing's rebuilt yet at that point). Falls back to
# fetching it via nix-shell just for that one bootstrap case, rather than
# always paying that cost.
if command -v mkpasswd >/dev/null 2>&1; then
    hash="$(printf '%s' "$pass1" | mkpasswd -m sha-512 -s)"
else
    echo "mkpasswd not on \$PATH yet (pre-rebuild bootstrap) — fetching it via nix-shell..." >&2
    hash="$(printf '%s' "$pass1" | nix-shell -p mkpasswd --run "mkpasswd -m sha-512 -s")"
fi
unset pass1 pass2

sudo install -d -m 700 -o root -g root "$(dirname "$HASH_FILE")"
printf '%s\n' "$hash" | sudo tee "$HASH_FILE" > /dev/null
sudo chown root:root "$HASH_FILE"
sudo chmod 600 "$HASH_FILE"
unset hash

echo ""
echo "Password hash written to $HASH_FILE (root:root, 600)."
if command -v pacnix >/dev/null 2>&1; then
    echo "Run 'pacnix rebuild' to deploy it."
else
    # pacnix itself is a Dotfiles-provided command (via scripts.nix) — on a
    # genuinely fresh system (install.sh's first run), nothing's been
    # rebuilt yet, so it doesn't exist on $PATH either.
    echo "Run 'sudo nixos-rebuild switch --flake /etc/nixos#herauxvalle' to deploy it"
    echo "('pacnix rebuild' isn't available until after that first rebuild)."
fi
