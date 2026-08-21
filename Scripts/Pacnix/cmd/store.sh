#!/usr/bin/env bash
# store.sh -- find nix store paths for a package name.
# Usage: pacnix store <name>   e.g. pacnix store firefox
#
# Store path basenames look like <32-char-hash>-<name>-<version>, plus
# assorted auxiliary outputs for the same package (e.g. kitty also produces
# kitty-<version>-terminfo, kitty-<version>-kitten, etc.) -- this only
# matches the plain "name-version" form (version anchored to the end, no
# trailing -suffix), so it reports the actual package, not its side outputs.
#
# Shows two things, since they can differ:
#   1. What's in /run/current-system's closure right now (what you're
#      actually running).
#   2. The highest version anywhere in /nix/store (could be newer or
#      older than what's active -- builds that haven't been garbage
#      collected yet).
set -euo pipefail

target="${1:-}"
if [ -z "$target" ]; then
    echo "usage: pacnix store <name>" >&2
    exit 1
fi

pattern=".*/[a-z0-9]{32}-${target}-[0-9][0-9a-zA-Z.]*"

echo "=== in the current system (/run/current-system) ==="
current_matches="$(nix-store -q --requisites /run/current-system 2>/dev/null | grep -E -- "$pattern\$" || true)"
if [ -n "$current_matches" ]; then
    echo "$current_matches"
else
    echo "(not found in the current system's closure)"
fi

echo ""
echo "=== highest version anywhere in /nix/store ==="
latest="$(find /nix/store -maxdepth 1 -type d -regextype posix-extended -regex "$pattern" 2>/dev/null \
    | awk -F/ '{print substr($NF, 34) "\t" $0}' \
    | sort -V \
    | tail -1 \
    | cut -f2-)"

if [ -n "$latest" ]; then
    echo "$latest"
else
    echo "(no match found in /nix/store -- check for typos, or try a shorter/more exact name)"
fi
