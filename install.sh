#!/usr/bin/env bash
# &desc: "Install dispatcher -- --format wipes/partitions a disk via disko, --setup symlinks /etc/nixos and seeds the password. Actual logic lives in Installation/."
#
# install.sh -- entry point, flag-required so nothing destructive can
# ever run by accident just from running this script bare:
#   --format   Installation/format.sh -- DESTRUCTIVE. Wipes and
#              partitions/formats a disk via disko, for a genuinely
#              fresh install. Confirms extensively before touching
#              anything -- see that script's own comment.
#   --setup    Installation/setup.sh -- what this script used to be
#              (the same logic, moved and renamed). Symlinks /etc/nixos,
#              regenerates hardware-configuration.nix, seeds the initial
#              password. Assumes an already-partitioned, already-booted
#              system -- run --format first if starting from a blank disk.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
    echo "Usage: $0 --setup | --format" >&2
    echo "" >&2
    echo "  --setup   Symlink /etc/nixos, regenerate hardware-configuration.nix, seed the password." >&2
    echo "            (Installation/setup.sh -- assumes an already-partitioned, booted system.)" >&2
    echo "" >&2
    echo "  --format  DESTRUCTIVE. Partition/format a disk via disko for a fresh install." >&2
    echo "            (Installation/format.sh -- asks which disk, confirms repeatedly.)" >&2
    exit 1
}

if [ "$#" -ne 1 ]; then
    usage
fi

case "$1" in
    --setup)
        exec bash "$REPO_ROOT/Installation/setup.sh"
        ;;
    --format)
        exec bash "$REPO_ROOT/Installation/format.sh"
        ;;
    *)
        usage
        ;;
esac
