#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

# Builds the live-install ISO from the redacted, GitHub-published copy
# of this flake, not the local checkout -- same reasoning as
# cmd/published.sh (which this reuses the clone/attr-resolution logic
# from): the local flake still has every real value in it, but the
# whole point of the ISO is to hand out something that's already had
# Nixos/config/github/{redactions,replacements}.nix strip personal
# values (self-hosted services, sudo-keyfile, etc. -- see Nixos/iso.nix
# for what's additionally forced off specifically for live media).
remoteUrl="$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.vars.backup.dotfilesBackup.remoteUrl")"
branch="$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.vars.backup.dotfilesBackup.branch")"
httpsUrl="$(printf '%s' "$remoteUrl" | sed -E 's#^git@([^:]+):#https://\1/#')"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "cloning $httpsUrl ($branch)..."
git clone --quiet --depth 1 --branch "$branch" "$httpsUrl" "$tmpdir/repo"
cd "$tmpdir/repo"

mapfile -t resolved < <(resolve_flake_attrs .)
isoAttr="${resolved[1]:-}"
if [ -z "$isoAttr" ]; then
    echo "No '-iso' nixosConfigurations attribute found in the published repo." >&2
    exit 1
fi

echo "building .#nixosConfigurations.$isoAttr.config.system.build.isoImage..."
# --impure: Nixos/iso.nix reads the embedded flake's source path via
# builtins.getEnv (ISO_DOTFILES_SOURCE), same pattern as
# partitioning.nix's DISKO_TARGET_DEVICE/DISKO_ROOT_KEYFILE. Pointed at
# this very clone -- the ISO embeds a snapshot of the exact redacted
# copy it's built from, not a separate one.
export ISO_DOTFILES_SOURCE="$tmpdir/repo"
isoResult="$(nix build --impure --no-link --print-out-paths ".#nixosConfigurations.$isoAttr.config.system.build.isoImage")"

isoFile="$(find "$isoResult/iso" -maxdepth 1 -name '*.iso' | head -n1)"
if [ -z "$isoFile" ]; then
    echo "Build succeeded but no .iso file found under $isoResult/iso." >&2
    exit 1
fi

dest="$OLDPWD/$(basename "$isoFile")"
cp "$isoFile" "$dest"
chmod +w "$dest"

echo ""
echo "ISO built: $dest ($(du -h "$dest" | cut -f1))"
