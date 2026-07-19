#!/usr/bin/env bash
# secrets passwd -- change the account password, and re-declare its hash
# for users.users.herauxvalle.hashedPasswordFile in Nixos/modules/system/users.nix.
#
# Runs the real `passwd` command (typed once: current, new, confirm --
# same prompts `passwd` always asks, nothing extra bolted on). Two things
# fall out of that for free: /etc/shadow gets the new password live
# immediately, and GNOME Keyring's login keyring gets re-keyed to match
# it via pam_gnome_keyring (config/system/keyring.nix wires that into
# this exact PAM service) -- no separate keyring step needed.
#
# The resulting hash is then copied verbatim out of /etc/shadow into the
# declarative hash file below, so there's no separate hashing step and
# no risk of it drifting from what `passwd` just set.
#
# hashedPasswordFile (a file reference, read by the activation script at
# rebuild time) instead of hashedPassword (a literal hash string baked
# directly into the Nix config) keeps the hash out of the world-readable
# /nix/store. That file deliberately lives outside /etc/nixos -- /etc/nixos
# IS the Dotfiles checkout (symlinked there by install.sh), so anything
# placed inside it would sit inside the checkout itself, at real risk of
# ending up git-tracked/shared. /etc/nixos-secrets/ is a sibling directory
# instead, never part of the checkout.
#
# A rebuild is still what actually deploys the hash declaratively -- this
# only writes the file (`passwd` above already applied it live).
#
# Forgot your current password entirely? This script can't help (passwd
# needs it) -- delete the hash file instead and rebuild; users.nix's own
# safety net falls back to a known password (changeme) when it's missing.
set -euo pipefail

HASH_FILE="/etc/nixos-secrets/herauxvalle-password.hash"

passwd

hash="$(sudo getent shadow "$(id -un)" | cut -d: -f2)"

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
    # pacnix itself is a Dotfiles-provided command (via scripts.nix) -- on a
    # genuinely fresh system (install.sh's first run), nothing's been
    # rebuilt yet, so it doesn't exist on $PATH either.
    echo "Run 'sudo nixos-rebuild switch --flake /etc/nixos#herauxvalle' to deploy it"
    echo "('pacnix rebuild' isn't available until after that first rebuild)."
fi
