#!/usr/bin/env bash
# plugins.sh -- generate a ready-to-paste mkPlugin { ... } block for
# Nixos/home/hyprland-plugins.nix from just a git URL.
#
# Runs silently and prints exactly one thing: the finished block on
# success, or one clear failure message (plus what's already known) if it
# can't finish on its own. No retries, no hardcoded dependency-name table --
# mapping an arbitrary missing pkg-config module to its nixpkgs package in
# general requires either a curated list (limited) or a full nixpkgs index
# (nix-index/nix search, a genuinely heavy one-time scan) -- neither is
# worth it here, so a real missing dep is just reported and left for a
# human to add to extraBuildInputs.
#
# The trial build below is throwaway: `nix build --no-link` creates no GC
# root, so nothing sticks around because of this script -- the only build
# that actually persists is the real one home-manager does once you paste
# the block in and rebuild.
#
# Usage: pacnix plugins <git-url> [rev]
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

url="${1:-}"
rev="${2:-}"

if [ -z "$url" ]; then
    echo "usage: pacnix plugins <git-url> [rev]" >&2
    exit 1
fi

json="$(nix run nixpkgs#nix-prefetch-git -- --url "$url" ${rev:+--rev "$rev"} --quiet 2>/dev/null)"

got_rev="$(grep -oP '"rev"\s*:\s*"\K[^"]+' <<< "$json" || true)"
hash="$(grep -oP '"hash"\s*:\s*"\K[^"]+' <<< "$json" || true)"
commit_date="$(grep -oP '"date"\s*:\s*"\K[^"]+' <<< "$json" | cut -c1-10 || true)"

if [ -z "$got_rev" ] || [ -z "$hash" ]; then
    echo "failed to prefetch $url -- check the URL/rev" >&2
    exit 1
fi

name_guess="$(basename "$url" .git)"
version="0-unstable-${commit_date:-unknown}"
flake_real="$(readlink -f "$FLAKE")"

build_err="$(mktemp)"
trap 'rm -f "$build_err"' EXIT

build_expr="
let
  pkgs = (builtins.getFlake \"$flake_real\").nixosConfigurations.$HOST.pkgs;
in
pkgs.hyprland.stdenv.mkDerivation {
  pname = \"hyprland-${name_guess}\";
  version = \"${version}\";
  src = pkgs.fetchgit {
    url = \"${url}\";
    rev = \"${got_rev}\";
    hash = \"${hash}\";
  };
  nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];
  buildInputs = [ pkgs.hyprland ] ++ pkgs.hyprland.buildInputs;
  dontStrip = true;
}
"

if out_path="$(nix build --impure --no-link --print-out-paths --expr "$build_expr" 2>"$build_err")"; then
    so_files=()
    while IFS= read -r f; do so_files+=("$f"); done < <(find "$out_path/lib" -maxdepth 1 -name '*.so' -printf '%f\n' 2>/dev/null)

    if [ "${#so_files[@]}" -eq 0 ]; then
        echo "build succeeded but no .so found under $out_path/lib -- inspect it manually:" >&2
        echo "  $out_path/lib" >&2
        exit 1
    fi

    for so_file in "${so_files[@]}"; do
        name="${so_file#lib}"
        name="${name%.so}"
        printf '\n    (mkPlugin {\n      name = "%s";\n      url = "%s";\n      rev = "%s";\n      hash = "%s";\n      version = "%s";\n    })\n' \
            "$name" "$url" "$got_rev" "$hash" "$version"
    done
else
    missing=()
    while IFS= read -r m; do missing+=("$m"); done < <(grep -oP "No package '\K[^']+" "$build_err" | sort -u)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "build failed -- missing pkg-config module(s): ${missing[*]}" >&2
        echo "add the matching nixpkgs package(s) to extraBuildInputs below and rebuild." >&2
    else
        echo "build failed for a reason other than a missing pkg-config module --" >&2
        echo "last part of the error:" >&2
        echo "" >&2
        tail -20 "$build_err" >&2
    fi
    echo "" >&2
    echo "also double-check 'name' below against the .so it actually produces once it" >&2
    echo "builds -- guessed from the repo name here, so it may be wrong." >&2

    printf '\n    (mkPlugin {\n      name = "%s";\n      url = "%s";\n      rev = "%s";\n      hash = "%s";\n      version = "%s";\n    })\n' \
        "$name_guess" "$url" "$got_rev" "$hash" "$version"
    exit 1
fi
