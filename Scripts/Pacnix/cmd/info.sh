#!/usr/bin/env bash
# info.sh -- detailed, machine-parsable system report.
#
# Each field is its own case arm in field_value() and computed lazily --
# only fields actually selected get run. Some are cheap (uname, readlink)
# but a few walk the whole store or the full closure (multiple seconds),
# so an external tool asking for one cheap field (e.g. `-o PACKAGES`)
# shouldn't pay for the expensive ones just because they're in the
# default set.
#
# Output modes (mirrors lsblk's -o/-n/-P):
#   default        "LABEL: value" aligned, all fields
#   -o F1,F2,...   select/order fields (case-insensitive), `-o list` to
#                  print available field names and exit
#   -n             values only, no labels -- one per line, in -o order,
#                  e.g. `pacnix info -o STORE_SIZE -n` for a single clean
#                  value to pipe into sort/cut/whatever
#   -p             KEY="value" pairs, one per line -- eval-able in bash,
#                  trivially regex-parsable elsewhere
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

field_order=(NIXOS_VERSION KERNEL HOST GENERATIONS CURRENT_GEN GRUB_ENTRIES STORE_SIZE STORE_PATHS CLOSURE_SIZE CLOSURE_PATHS PACKAGES GCROOTS DISK_FREE DISK_USED_PCT)

field_desc() {
    case "$1" in
        NIXOS_VERSION) echo "nixos-version string (release, codename)" ;;
        KERNEL) echo "running kernel release (uname -r)" ;;
        HOST) echo "flake hostname this system was built as (\$HOST)" ;;
        GENERATIONS) echo "total system generations kept (/nix/var/nix/profiles/system-*-link), including ones no longer in the GRUB menu" ;;
        CURRENT_GEN) echo "generation number currently booted (/nix/var/nix/profiles/system)" ;;
        GRUB_ENTRIES) echo "menu entries actually in grub.cfg right now, capped by boot.loader.grub.configurationLimit" ;;
        STORE_SIZE) echo "on-disk size of the whole /nix/store -- every generation, every build dependency, not just what's live" ;;
        STORE_PATHS) echo "top-level path count in /nix/store" ;;
        CLOSURE_SIZE) echo "on-disk size of just the running system's closure (/run/current-system)" ;;
        CLOSURE_PATHS) echo "full transitive closure path count for the running system (nix-store -q --requisites)" ;;
        PACKAGES) echo "packages directly on the running system's PATH (/run/current-system/sw) -- the environment.systemPackages-level count, not the transitive closure" ;;
        GCROOTS) echo "registered GC roots (/nix/var/nix/gcroots) -- anything reachable from these survives nix-collect-garbage" ;;
        DISK_FREE) echo "free space on the filesystem backing /nix" ;;
        DISK_USED_PCT) echo "used% on the filesystem backing /nix" ;;
        *) echo "" ;;
    esac
}

field_value() {
    case "$1" in
        # Every arm below is best-effort and ends in `|| true`: with
        # pipefail on, a pipe like `grep pattern | wc -l` still reports
        # the *grep* stage's exit code (1 on zero matches) even though
        # wc -l already printed the correct "0" -- set -e would treat
        # that as this one field failing and kill the whole report. The
        # `|| true` launders the exit status only; stdout already
        # produced by the pipeline is unaffected.
        NIXOS_VERSION) nixos-version 2>/dev/null || true ;;
        KERNEL) uname -r ;;
        HOST) echo "$HOST" ;;
        GENERATIONS) ls /nix/var/nix/profiles 2>/dev/null | grep -E '^system-[0-9]+-link$' | wc -l || true ;;
        CURRENT_GEN) readlink /nix/var/nix/profiles/system 2>/dev/null | grep -oE '[0-9]+' || echo "?" ;;
        GRUB_ENTRIES) grep '^menuentry' /boot/grub/grub.cfg 2>/dev/null | wc -l || true ;;
        STORE_SIZE) du -sh /nix/store 2>/dev/null | cut -f1 || true ;;
        STORE_PATHS) ls /nix/store 2>/dev/null | wc -l || true ;;
        CLOSURE_SIZE) nix path-info -Sh /run/current-system 2>/dev/null | awk '{print $2, $3}' || true ;;
        CLOSURE_PATHS) nix-store -q --requisites /run/current-system 2>/dev/null | wc -l || true ;;
        PACKAGES) nix-store -q --references /run/current-system/sw 2>/dev/null | wc -l || true ;;
        GCROOTS) find /nix/var/nix/gcroots -maxdepth 3 2>/dev/null | wc -l || true ;;
        DISK_FREE) df -h /nix 2>/dev/null | awk 'NR==2{print $4}' || true ;;
        DISK_USED_PCT) df -h /nix 2>/dev/null | awk 'NR==2{print $5}' || true ;;
        *) echo "unknown field: $1" >&2; return 1 ;;
    esac
}

selected=("${field_order[@]}")
mode="labels"   # labels | noheadings | pairs

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            arg="${2:-}"
            if [ "$arg" = "list" ] || [ "$arg" = "help" ]; then
                for f in "${field_order[@]}"; do
                    printf "%-15s %s\n" "$f" "$(field_desc "$f")"
                done
                exit 0
            fi
            IFS=',' read -r -a selected <<< "${arg^^}"
            shift 2
            ;;
        -n|--noheadings) mode="noheadings"; shift ;;
        -p|--pairs) mode="pairs"; shift ;;
        -l|--list)
            for f in "${field_order[@]}"; do
                printf "%-15s %s\n" "$f" "$(field_desc "$f")"
            done
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

for f in "${selected[@]}"; do
    value="$(field_value "$f")"
    case "$mode" in
        labels) printf "%-15s %s\n" "${f}:" "$value" ;;
        noheadings) printf "%s\n" "$value" ;;
        pairs) printf '%s="%s"\n' "$f" "$value" ;;
    esac
done
