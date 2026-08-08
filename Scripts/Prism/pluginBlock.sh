#!/usr/bin/env bash
# &desc: "Given a plugin/mod jar download URL, prefetches its sha256 and prints a ready-to-paste symlinks.\"plugins/<name>.jar\" = pkgs.fetchurl { ... }; block for nix-minecraft server configs."
set -euo pipefail

URL="${1:-}"
if [[ -z "$URL" ]]; then
    echo "Usage: $0 <jar-url> [dest-name.jar]" >&2
    exit 1
fi

DEST="${2:-}"
if [[ -z "$DEST" ]]; then
    # decode %xx and strip query string, keep basename
    DEST=$(python3 -c '
import sys, urllib.parse, posixpath
u = urllib.parse.urlparse(sys.argv[1])
print(posixpath.basename(urllib.parse.unquote(u.path)))
' "$URL")
fi

if [[ "$DEST" != *.jar ]]; then
    echo "Resolved filename '$DEST' doesn't look like a jar -- pass an explicit dest-name.jar as \$2." >&2
    exit 1
fi

STORE_HASH=$(nix-prefetch-url --type sha256 "$URL" 2>/dev/null | tail -1)
if [[ -z "$STORE_HASH" ]]; then
    echo "nix-prefetch-url failed for $URL" >&2
    exit 1
fi

SRI_HASH=$(nix hash convert --hash-algo sha256 --to sri "$STORE_HASH" 2>/dev/null \
    || nix hash to-sri --type sha256 "$STORE_HASH")

cat <<EOF

  "plugins/${DEST}" = pkgs.fetchurl {
    url = "${URL}";
    hash = "${SRI_HASH}";
  };
EOF
