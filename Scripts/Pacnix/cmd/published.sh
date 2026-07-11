#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

# test-build builds YOUR local flake, which still has every real value in
# it -- it can never catch a redactValues/replaceValues entry that leaves
# the PUBLISHED copy broken (required option commented out, a key that no
# longer resolves once redacted, etc.), since that copy doesn't exist until
# after a push. This clones the actual pushed repo fresh, over anonymous
# HTTPS (not the root-owned SSH deploy key -- the whole point is proving a
# stranger without that key can pull and build it too), and dry-run builds
# it exactly like test-build does locally.
remoteUrl="$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.vars.dotfilesBackup.remoteUrl")"
branch="$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.vars.dotfilesBackup.branch")"
httpsUrl="$(printf '%s' "$remoteUrl" | sed -E 's#^git@([^:]+):#https://\1/#')"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "cloning $httpsUrl ($branch)..."
git clone --quiet --depth 1 --branch "$branch" "$httpsUrl" "$tmpdir/repo"
cd "$tmpdir/repo"

# The published attribute name isn't necessarily "$HOST" -- replaceValues
# may have renamed nixosConfigurations.<name> to a placeholder (see
# Nixos/config/excludes.nix). Read back whatever name is actually there
# instead of assuming it matches the local one.
attr="$(nix eval --json .#nixosConfigurations --apply builtins.attrNames --no-write-lock-file \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)[0])')"

echo "building .#nixosConfigurations.$attr.config.system.build.toplevel (dry-run)..."
nix build --dry-run --no-write-lock-file ".#nixosConfigurations.$attr.config.system.build.toplevel"

echo "OK: published repo ($httpsUrl#$branch, nixosConfigurations.$attr) evaluates and resolves cleanly."
