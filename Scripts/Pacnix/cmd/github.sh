#!/usr/bin/env bash
# pacnix github push/release -- thin passthrough to the Nix-packaged
# gitctl CLI (modules/packages/repos/repos.nix + lib/), which reads the
# declarative registry at config.vars.packages.repos. See `gitctl help`
# (or `pacnix github help`) for the full command reference.
set -euo pipefail

if ! command -v gitctl > /dev/null 2>&1; then
    echo "gitctl not found on PATH -- run 'pacnix rebuild' first (it's installed by" >&2
    echo "modules/packages/repos/repos.nix's home.packages)." >&2
    exit 1
fi

exec gitctl "$@"
