#!/usr/bin/env bash
# &desc: "install.sh --build-iso -- curl-pipeable live-install ISO builder. Only real dependency is Nix (curl/tar cover the rest, no git needed). Always fetches the public repo fresh into a tmp dir (never builds off a local checkout, which might have unredacted values) and drops the .iso in ~/Downloads."
set -euo pipefail

command -v nix >/dev/null 2>&1 || {
    echo "Nix not found -- install it first: https://nixos.org/download" >&2
    exit 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "downloading HerauxValle/nixos..."
# Plain tarball, not git clone -- one fewer dependency to expect on a
# machine that only has Nix installed. Flakes don't need the source to
# actually be a git repo for a local build, just a real directory.
mkdir -p "$tmpdir/nixos"
curl -fsSL "https://github.com/HerauxValle/nixos/archive/refs/heads/main.tar.gz" \
    | tar -xz -C "$tmpdir/nixos" --strip-components=1
cd "$tmpdir/nixos"

echo "building .#nixosConfigurations.maxmustermann-iso.config.system.build.isoImage..."
export ISO_DOTFILES_SOURCE="$PWD"
nix build --impure --extra-experimental-features 'nix-command flakes' \
    '.#nixosConfigurations.maxmustermann-iso.config.system.build.isoImage'

isoFile="$(find result/iso -maxdepth 1 -name '*.iso' | head -n1)"
if [ -z "$isoFile" ]; then
    echo "Build succeeded but no .iso file found under result/iso." >&2
    exit 1
fi

mkdir -p "$HOME/Downloads"
dest="$HOME/Downloads/$(basename "$isoFile")"
cp "$isoFile" "$dest"

echo ""
echo "ISO built: $dest ($(du -h "$dest" | cut -f1))"
