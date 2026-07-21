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
remoteUrl="$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.vars.backup.dotfilesBackup.remoteUrl")"
branch="$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.vars.backup.dotfilesBackup.branch")"
httpsUrl="$(printf '%s' "$remoteUrl" | sed -E 's#^git@([^:]+):#https://\1/#')"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "cloning $httpsUrl ($branch)..."
git clone --quiet --depth 1 --branch "$branch" "$httpsUrl" "$tmpdir/repo"
cd "$tmpdir/repo"

# The published attribute names aren't necessarily "$HOST"/"$HOST-iso"
# -- replaceValues may have renamed both nixosConfigurations.<name> and
# nixosConfigurations.<name>-iso to placeholders (see Nixos/config/
# github/replacements.nix). resolve_flake_attrs (lib/common.sh) reads
# back whatever names are actually there and splits the real
# installed-system one from the live-ISO one, instead of indexing [0]
# (which only ever worked back when there was exactly one attribute).
mapfile -t resolved < <(resolve_flake_attrs .)
attr="${resolved[0]}"
isoAttr="${resolved[1]:-}"

echo "building .#nixosConfigurations.$attr.config.system.build.toplevel (dry-run)..."
nix build --dry-run --no-write-lock-file ".#nixosConfigurations.$attr.config.system.build.toplevel"
echo "OK: published repo ($httpsUrl#$branch, nixosConfigurations.$attr) evaluates and resolves cleanly."

if [ -n "$isoAttr" ]; then
    echo ""
    echo "building .#nixosConfigurations.$isoAttr.config.system.build.isoImage (dry-run)..."
    # --impure: Nixos/iso.nix reads the embedded flake's source path via
    # builtins.getEnv (ISO_DOTFILES_SOURCE), same as cmd/release.sh --
    # this check doesn't need a real embedded copy, just something that
    # exists, so it points at the clone itself.
    ISO_DOTFILES_SOURCE="$tmpdir/repo" nix build --impure --dry-run --no-write-lock-file ".#nixosConfigurations.$isoAttr.config.system.build.isoImage"
    echo "OK: published repo's live-ISO output (nixosConfigurations.$isoAttr) evaluates and resolves cleanly."
else
    echo "" >&2
    echo "Warning: no '-iso' nixosConfigurations attribute found in the published repo -- skipping its isoImage check." >&2
fi
