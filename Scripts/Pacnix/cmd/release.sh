#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

cleanupDirs=()
cleanup() { local d; for d in "${cleanupDirs[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# Publishes an existing ISO as a real GitHub Release (tag + release +
# chunked assets) on the repo Nix-configured at
# vars.backup.dotfilesBackup.githubRepo -- reuses the classic PAT
# `secrets github add classic` already deploys for gitctl (see
# modules/packages/repos/repos.nix), no separate token/secret needed.
# Deliberately does NOT push repo content anywhere -- that's backup/'s
# own job (with its own redaction pipeline); this only ever uploads the
# one file it's given. GitHub caps a single release asset at ~2GB, so
# the ISO is split into numbered chunks and reassembled with `cat` on
# the other end.
publish_iso() {
    local isoFile="$1"
    local tokenFile="$HOME/.config/gitctl/classic-token"
    if [ ! -f "$tokenFile" ]; then
        echo "no classic token -- run 'secrets github add classic' then 'pacnix rebuild'" >&2
        exit 1
    fi
    local token githubRepo tag payload response release_id chunkDir part partName http_code respFile

    token="$(cat "$tokenFile")"
    githubRepo="$(nix eval --raw "$FLAKE#nixosConfigurations.$HOST.config.vars.backup.dotfilesBackup.githubRepo")"
    tag="$(basename "$isoFile" .iso)"

    echo "publishing $(basename "$isoFile") to $githubRepo as release '$tag'..."

    payload="$(jq -n --arg tag "$tag" \
        --arg body "Live-install ISO, split into parts under ~2GB (GitHub's per-asset limit). Reassemble with: cat ${tag}.part-* > ${tag}.iso" \
        '{tag_name:$tag, name:$tag, body:$body, draft:false, prerelease:false}')"

    response="$(curl -sS -X POST \
        -H "Authorization: token $token" -H "Content-Type: application/json" \
        -d "$payload" "https://api.github.com/repos/$githubRepo/releases")"
    release_id="$(jq -r '.id // empty' <<< "$response")"
    if [ -z "$release_id" ]; then
        echo "release creation failed:" >&2
        jq -r '.message // .' <<< "$response" >&2
        exit 1
    fi
    echo "release '$tag' created (id $release_id)"

    chunkDir="$(mktemp -d)"
    cleanupDirs+=("$chunkDir")
    respFile="$chunkDir/.upload-response.json"
    split -b 1900M -d -a 2 "$isoFile" "$chunkDir/${tag}.part-"

    for part in "$chunkDir/${tag}.part-"*; do
        partName="$(basename "$part")"
        echo "uploading $partName ($(du -h "$part" | cut -f1))..."
        http_code="$(curl -sS -o "$respFile" -w '%{http_code}' \
            -X POST -H "Authorization: token $token" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "@$part" \
            "https://uploads.github.com/repos/$githubRepo/releases/$release_id/assets?name=$partName")"
        if [[ "$http_code" != 2* ]]; then
            echo "upload failed for $partName (HTTP $http_code):" >&2
            cat "$respFile" >&2
            exit 1
        fi
    done

    echo ""
    echo "Published: https://github.com/$githubRepo/releases/tag/$tag"
    echo "Reassemble on the other end with: cat ${tag}.part-* > ${tag}.iso"
}

if [ $# -ge 1 ]; then
    isoPath="$1"
    if [ ! -f "$isoPath" ]; then
        echo "no such file: $isoPath" >&2
        exit 1
    fi
    publish_iso "$isoPath"
    exit 0
fi

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
cleanupDirs+=("$tmpdir")

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
