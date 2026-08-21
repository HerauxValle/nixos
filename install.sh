#!/usr/bin/env bash
# &desc: "Install dispatcher -- --format wipes/partitions a disk via disko, --setup symlinks /etc/nixos and seeds the password, --build-iso builds the live ISO standalone. Actual logic lives in Installation/."
#
# install.sh -- entry point, flag-required so nothing destructive can
# ever run by accident just from running this script bare:
#   --format     Installation/format.sh -- DESTRUCTIVE. Wipes and
#                partitions/formats a disk via disko, for a genuinely
#                fresh install. Confirms extensively before touching
#                anything -- see that script's own comment.
#   --setup      Installation/setup.sh -- what this script used to be
#                (the same logic, moved and renamed). Symlinks /etc/nixos,
#                regenerates hardware-configuration.nix, seeds the initial
#                password. Assumes an already-partitioned, already-booted
#                system -- run --format first if starting from a blank disk.
#   --build-iso  Installation/build-iso.sh -- builds the live-install ISO.
#                Needs only Nix (no NixOS, no existing checkout). The one
#                flag meant to be curl-piped on a machine that's never
#                seen this repo before -- when run that way, BASH_SOURCE
#                doesn't resolve to a real file, so there's no sibling
#                Installation/ to dispatch to. Detected below: falls back
#                to curling build-iso.sh straight from GitHub and running
#                that instead of failing on a missing local file.
set -euo pipefail

# Piped (curl ... | bash) means BASH_SOURCE[0] isn't a real path on disk --
# realpath fails, so REPO_ROOT just becomes empty instead of aborting the
# whole script here. Only --build-iso tolerates that (see below); --setup/
# --format still require a real checkout, same as always.
REPO_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" 2>/dev/null && pwd)" || REPO_ROOT=""

usage() {
    echo "Usage: $0 --setup | --format | --build-iso" >&2
    echo "" >&2
    echo "  --setup      Symlink /etc/nixos, regenerate hardware-configuration.nix, seed the password." >&2
    echo "               (Installation/setup.sh -- assumes an already-partitioned, booted system.)" >&2
    echo "" >&2
    echo "  --format     DESTRUCTIVE. Partition/format a disk via disko for a fresh install." >&2
    echo "               (Installation/format.sh -- asks which disk, confirms repeatedly.)" >&2
    echo "" >&2
    echo "  --build-iso  Build the live-install ISO. Only needs Nix installed -- no NixOS," >&2
    echo "               no checkout required, safe to curl-pipe on any machine." >&2
    echo "               (Installation/build-iso.sh)" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage
fi

# Both --setup and --format operate on THIS checkout (symlink /etc/nixos
# to it, partition a disk per its config) -- there's no "fetch it fresh"
# fallback that would make sense for either, unlike --build-iso. Fail
# with a clear reason instead of the raw "No such file or directory"
# exec would otherwise throw.
requireRepoRoot() {
    if [ -z "$REPO_ROOT" ]; then
        echo "error: $1 needs a real checkout on disk, not a curl pipe -- BASH_SOURCE didn't resolve to a file." >&2
        echo "clone the repo first: git clone https://github.com/HerauxValle/nixos.git && cd nixos && ./install.sh $1" >&2
        exit 1
    fi
}

case "$1" in
    --setup)
        requireRepoRoot --setup
        exec bash "$REPO_ROOT/Installation/setup.sh"
        ;;
    --format)
        requireRepoRoot --format
        exec bash "$REPO_ROOT/Installation/format.sh"
        ;;
    --build-iso)
        if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/Installation/build-iso.sh" ]; then
            exec bash "$REPO_ROOT/Installation/build-iso.sh"
        else
            echo "note: no local checkout found (running via curl pipe?) -- fetching build-iso.sh directly." >&2
            exec bash -c "curl -fsSL https://raw.githubusercontent.com/HerauxValle/nixos/main/Installation/build-iso.sh | bash"
        fi
        ;;
    *)
        usage
        ;;
esac
