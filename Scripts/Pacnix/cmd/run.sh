#!/usr/bin/env bash
&desc: pacnix run <pkg> -- temporary nix shell, nothing persistent
# run.sh -- imperatively drop into a package temporarily, nix-shell style.
# Usage: pacnix run <pkg> [pkg...]
#
# Just `nix shell nixpkgs#<pkg>...` -- not installed onto the system, not
# added to any profile or config, gone once the shell exits and eligible
# for GC like any other nix shell closure. Use `pacnix packages` for an
# actual persistent install.
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: pacnix run <pkg> [pkg...]" >&2
    exit 1
fi

refs=()
for pkg in "$@"; do
    refs+=("nixpkgs#${pkg}")
done

exec nix shell "${refs[@]}"
