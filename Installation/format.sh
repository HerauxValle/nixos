#!/usr/bin/env bash
# &desc: "DESTRUCTIVE disko format+mount step for a fresh install -- asks which disk, confirms twice, builds and runs disko against Nixos/partitioning.nix. Run via '../install.sh --format', not directly."
#
# format.sh -- wipes and partitions/formats a disk per Nixos/partitioning.nix,
# then mounts it under /mnt. This is the disko half of a fresh install; run
# ../install.sh --setup afterward (from the newly-mounted system, or after
# a plain `nixos-install`) to seed the password and link /etc/nixos.
#
# Needs $DISKO_ROOT_KEYFILE already exported -- the real LUKS keyfile's
# path (see Nixos/partitioning.nix's own comment on passwordFile). This
# script doesn't touch, generate, or ask for that; it only asks for the
# target disk. Deliberately not automated further than that -- picking
# the WRONG disk here is unrecoverable, so every step that matters is a
# separate, explicit confirmation instead of one combined prompt.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"

echo ""
echo "=========================================================================="
echo " DESTRUCTIVE: this WIPES whichever disk you choose below -- partition"
echo " table, every filesystem, everything on it. There is no undo."
echo "=========================================================================="
echo ""

if [ -z "${DISKO_ROOT_KEYFILE:-}" ]; then
    echo "DISKO_ROOT_KEYFILE is not set." >&2
    echo "Export it to the real LUKS keyfile's path before running this script." >&2
    exit 1
fi

echo "Whole disks on this machine:"
echo ""
lsblk -d -o NAME,SIZE,MODEL,SERIAL,TYPE
echo ""
echo "Stable identifiers for each (pick one of these paths below, not a"
echo "bare /dev/sdX -- device letters aren't guaranteed stable):"
echo ""
ls -la /dev/disk/by-id/ | grep -v -- '-part[0-9]*$' | grep -v '^total\|^d'
echo ""

read -r -p "Target disk (full /dev/disk/by-id/... path): " chosen
if [ -z "$chosen" ] || [ ! -e "$chosen" ]; then
    echo "'$chosen' doesn't exist. Aborting, nothing touched." >&2
    exit 1
fi

resolved="$(readlink -f "$chosen")"
echo ""
echo "You chose:        $chosen"
echo "Which resolves to: $resolved"
echo ""
read -r -p "Type that resolved path again to confirm you want to WIPE it: " confirm
if [ "$confirm" != "$resolved" ]; then
    echo "Confirmation didn't match. Aborting, nothing touched." >&2
    exit 1
fi

export DISKO_TARGET_DEVICE="$chosen"

# Resolved instead of hardcoded "herauxvalle" -- this same script also
# runs against the redacted flake embedded on the live-install ISO
# (see Scripts/Pacnix/cmd/install.sh), where Nixos/config/github/
# replacements.nix has renamed that attribute to a placeholder.
# Filters out the "-iso" live-media output (nixosConfigurations.
# herauxvalle-iso in flake.nix) so this always targets the real
# installed-system config, never the live-boot one.
echo ""
echo "Resolving the installed-system flake attribute..."
attr="$(nix eval --json --no-write-lock-file "$REPO_ROOT#nixosConfigurations" --apply builtins.attrNames \
    | python3 -c 'import json, sys
names = [n for n in json.load(sys.stdin) if not n.endswith("-iso")]
assert len(names) == 1, f"expected exactly one non-iso nixosConfigurations attribute, found {names}"
print(names[0])')"
echo "Target: nixosConfigurations.$attr"

echo ""
echo "Building disko's format + mount scripts (nothing on disk touched yet)..."
format_script="$(nix build --impure --no-link --print-out-paths "$REPO_ROOT#nixosConfigurations.$attr.config.system.build.format")"
mount_script="$(nix build --impure --no-link --print-out-paths "$REPO_ROOT#nixosConfigurations.$attr.config.system.build.mount")"

echo ""
echo "Last chance: about to format $resolved."
read -r -p "Type WIPE (all caps) to proceed: " final
if [ "$final" != "WIPE" ]; then
    echo "Aborting, nothing touched." >&2
    exit 1
fi

"$format_script/bin/disko-format"
"$mount_script/bin/disko-mount"

echo ""
echo "Disk formatted and mounted under /mnt."
echo "Next: nixos-install --root /mnt --flake $REPO_ROOT#$attr"
echo "Then boot into it and run ./install.sh --setup."
