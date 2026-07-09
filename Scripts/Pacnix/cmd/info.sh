#!/usr/bin/env bash
# info.sh -- detailed, machine-parsable system report. Everything the
# system has to offer: not just "how many packages" but where they came
# from (declarative system config vs home-manager vs imperative installs
# vs the full transitive closure), store internals you can't get from a
# single stock command (derivations vs built outputs, how many packages
# have more than one version sitting in the store right now), exact
# flake pins, config size, and systemd/boot health.
#
# Each field is its own case arm in field_value(), computed lazily --
# only fields actually selected get run. Some are cheap (uname, readlink)
# but a few walk the whole store or the full closure (multiple seconds),
# so an external tool asking for one cheap field (e.g. `-o PKGS_SYSTEM`)
# shouldn't pay for the expensive ones just because they're in the
# default set.
#
# Output modes (mirrors lsblk's -o/-n/-P):
#   default        grouped "LABEL: value" report, all fields
#   -o F1,F2,...   select/order fields (case-insensitive), `-o list` to
#                  print available field names, grouped, with
#                  descriptions
#   -n             values only, no labels -- one per line, in -o order,
#                  e.g. `pacnix info -o STORE_SIZE -n` for a single clean
#                  value to pipe into sort/cut/whatever
#   -p             KEY="value" pairs, one per line -- eval-able in bash,
#                  trivially regex-parsable elsewhere
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$DIR/../lib/common.sh"

# name:category pairs, in display order
field_order=(
    PKGS_SYSTEM:Packages PKGS_HOME:Packages PKGS_IMPERATIVE:Packages
    PKGS_DECLARED_TOTAL:Packages CLOSURE_PACKAGES:Packages

    STORE_SIZE:Store STORE_PATHS:Store STORE_DERIVATIONS:Store
    STORE_OUTPUTS:Store STORE_DUPES:Store CLOSURE_SIZE:Store NIX_DB_SIZE:Store

    GENERATIONS:Generations CURRENT_GEN:Generations GEN_AGE:Generations
    OLDEST_GEN_AGE:Generations GRUB_ENTRIES:Generations

    FLAKE_INPUTS:Flake FLAKE_INPUT_NAMES:Flake NIXPKGS_REV:Flake
    NIXPKGS_DATE:Flake CONFIG_MODULES:Flake CONFIG_LOC:Flake

    NIXOS_VERSION:System KERNEL:System HOST:System NIX_VERSION:System
    UPTIME:System BOOT_TIME:System KERNEL_MODULES:System
    SYSTEMD_UNITS:System SYSTEMD_ENABLED:System SYSTEMD_FAILED:System
    GCROOTS:System

    DISK_FREE:Disk DISK_USED_PCT:Disk NIX_FS:Disk
)
field_names=()
for entry in "${field_order[@]}"; do field_names+=("${entry%%:*}"); done

field_category() {
    for entry in "${field_order[@]}"; do
        [ "${entry%%:*}" = "$1" ] && { echo "${entry##*:}"; return; }
    done
}

field_desc() {
    case "$1" in
        PKGS_SYSTEM) echo "packages on the system PATH from environment.systemPackages (/run/current-system/sw)" ;;
        PKGS_HOME) echo "packages from home-manager's home.packages (/etc/profiles/per-user/\$USER's home-manager-path)" ;;
        PKGS_IMPERATIVE) echo "packages installed outside the flake via nix-env/nix profile -- non-zero means the system isn't fully declarative" ;;
        PKGS_DECLARED_TOTAL) echo "PKGS_SYSTEM + PKGS_HOME + PKGS_IMPERATIVE -- everything explicitly asked for, not counting transitive deps" ;;
        CLOSURE_PACKAGES) echo "full transitive closure path count for the running system (nix-store -q --requisites) -- everything actually needed to run it" ;;
        STORE_SIZE) echo "on-disk size of the whole /nix/store -- every generation, every build dependency, not just what's live" ;;
        STORE_PATHS) echo "top-level path count in /nix/store (derivations + built outputs)" ;;
        STORE_DERIVATIONS) echo "*.drv files in /nix/store -- build recipes, not build products" ;;
        STORE_OUTPUTS) echo "STORE_PATHS minus STORE_DERIVATIONS -- actual built packages/outputs present" ;;
        STORE_DUPES) echo "distinct package names with more than one version/hash simultaneously present in the store -- dedup/GC candidates" ;;
        CLOSURE_SIZE) echo "on-disk size of just the running system's closure (/run/current-system)" ;;
        NIX_DB_SIZE) echo "size of the Nix store registration database (/nix/var/nix/db)" ;;
        GENERATIONS) echo "total system generations kept (/nix/var/nix/profiles/system-*-link), including ones no longer in the GRUB menu" ;;
        CURRENT_GEN) echo "generation number currently booted (/nix/var/nix/profiles/system)" ;;
        GEN_AGE) echo "time since the current generation was created" ;;
        OLDEST_GEN_AGE) echo "time since the oldest kept generation was created" ;;
        GRUB_ENTRIES) echo "menu entries actually in grub.cfg right now, capped by boot.loader.grub.configurationLimit" ;;
        FLAKE_INPUTS) echo "direct inputs declared in flake.nix (not transitive/follows -- see flake.lock's root node)" ;;
        FLAKE_INPUT_NAMES) echo "names of the direct flake inputs" ;;
        NIXPKGS_REV) echo "locked nixpkgs commit (short rev) this system is pinned to" ;;
        NIXPKGS_DATE) echo "commit date of the locked nixpkgs revision" ;;
        CONFIG_MODULES) echo "*.nix file count under the Nixos/ config tree" ;;
        CONFIG_LOC) echo "total lines across all *.nix files under Nixos/" ;;
        NIXOS_VERSION) echo "nixos-version string (release, codename)" ;;
        KERNEL) echo "running kernel release (uname -r)" ;;
        HOST) echo "flake hostname this system was built as (\$HOST)" ;;
        NIX_VERSION) echo "nix package manager version" ;;
        UPTIME) echo "time since last boot" ;;
        BOOT_TIME) echo "last boot's total startup time (systemd-analyze time)" ;;
        KERNEL_MODULES) echo "currently loaded kernel modules (lsmod)" ;;
        SYSTEMD_UNITS) echo "total systemd units currently loaded" ;;
        SYSTEMD_ENABLED) echo "systemd unit files enabled at boot" ;;
        SYSTEMD_FAILED) echo "systemd units currently in a failed state -- should be 0" ;;
        GCROOTS) echo "registered GC roots (/nix/var/nix/gcroots) -- anything reachable from these survives nix-collect-garbage" ;;
        DISK_FREE) echo "free space on the filesystem backing /nix" ;;
        DISK_USED_PCT) echo "used% on the filesystem backing /nix" ;;
        NIX_FS) echo "filesystem type and source device backing /nix" ;;
        *) echo "" ;;
    esac
}

human_duration() {
    local s=$1 d h m
    d=$((s / 86400)); h=$(((s % 86400) / 3600)); m=$(((s % 3600) / 60))
    if [ "$d" -gt 0 ]; then printf "%dd %dh" "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf "%dh %dm" "$h" "$m"
    else printf "%dm" "$m"
    fi
}

# Every arm below is best-effort and ends in `|| true`: with pipefail on,
# a pipe like `grep pattern | wc -l` still reports the *grep* stage's
# exit code (1 on zero matches) even though wc -l already printed the
# correct "0" -- set -e would treat that as this one field failing and
# kill the whole report. The `|| true` launders the exit status only;
# stdout already produced by the pipeline is unaffected.
field_value() {
    case "$1" in
        PKGS_SYSTEM) nix-store -q --references /run/current-system/sw 2>/dev/null | wc -l || true ;;
        PKGS_HOME)
            hm_path="$(nix-store -q --references "/etc/profiles/per-user/${USER:-$(id -un)}" 2>/dev/null | grep -m1 'home-manager-path' || true)"
            [ -n "$hm_path" ] && { nix-store -q --references "$hm_path" 2>/dev/null | wc -l || true; } || echo 0
            ;;
        PKGS_IMPERATIVE) nix-env -q 2>/dev/null | wc -l || true ;;
        PKGS_DECLARED_TOTAL)
            echo $(( $(field_value PKGS_SYSTEM) + $(field_value PKGS_HOME) + $(field_value PKGS_IMPERATIVE) ))
            ;;
        CLOSURE_PACKAGES) nix-store -q --requisites /run/current-system 2>/dev/null | wc -l || true ;;
        STORE_SIZE) du -sh /nix/store 2>/dev/null | cut -f1 || true ;;
        STORE_PATHS) ls /nix/store 2>/dev/null | wc -l || true ;;
        STORE_DERIVATIONS) find /nix/store -maxdepth 1 -name '*.drv' 2>/dev/null | wc -l || true ;;
        STORE_OUTPUTS)
            echo $(( $(field_value STORE_PATHS) - $(field_value STORE_DERIVATIONS) ))
            ;;
        STORE_DUPES)
            ls /nix/store 2>/dev/null \
                | grep -E '^[a-z0-9]{32}-' \
                | sed -E 's/^[a-z0-9]{32}-//; s/-[0-9][0-9a-zA-Z.+_-]*$//' \
                | sort | uniq -c | awk '$1>1' | wc -l || true
            ;;
        CLOSURE_SIZE) nix path-info -Sh /run/current-system 2>/dev/null | awk '{print $2, $3}' || true ;;
        NIX_DB_SIZE) du -sh /nix/var/nix/db 2>/dev/null | cut -f1 || true ;;
        GENERATIONS) ls /nix/var/nix/profiles 2>/dev/null | grep -E '^system-[0-9]+-link$' | wc -l || true ;;
        CURRENT_GEN) readlink /nix/var/nix/profiles/system 2>/dev/null | grep -oE '[0-9]+' || echo "?" ;;
        GEN_AGE)
            mtime="$(stat -c '%Y' /nix/var/nix/profiles/system 2>/dev/null || true)"
            [ -n "$mtime" ] && human_duration "$(($(date +%s) - mtime))" || echo "?"
            ;;
        OLDEST_GEN_AGE)
            oldest="$( (stat -c '%Y' /nix/var/nix/profiles/system-*-link 2>/dev/null || true) | sort -n | head -1)"
            [ -n "$oldest" ] && human_duration "$(($(date +%s) - oldest))" || echo "?"
            ;;
        GRUB_ENTRIES) grep '^menuentry' /boot/grub/grub.cfg 2>/dev/null | wc -l || true ;;
        FLAKE_INPUTS) python3 -c "import json;print(len(json.load(open('$FLAKE/flake.lock'))['nodes']['root']['inputs']))" 2>/dev/null || echo "?" ;;
        FLAKE_INPUT_NAMES) python3 -c "import json;print(', '.join(json.load(open('$FLAKE/flake.lock'))['nodes']['root']['inputs'].keys()))" 2>/dev/null || echo "?" ;;
        NIXPKGS_REV) python3 -c "import json;print(json.load(open('$FLAKE/flake.lock'))['nodes']['nixpkgs']['locked'].get('rev','?')[:12])" 2>/dev/null || echo "?" ;;
        NIXPKGS_DATE) python3 -c "
import json, datetime
d = json.load(open('$FLAKE/flake.lock'))['nodes']['nixpkgs']['locked']
print(datetime.datetime.fromtimestamp(d['lastModified'], datetime.timezone.utc).strftime('%Y-%m-%d'))
" 2>/dev/null || echo "?" ;;
        CONFIG_MODULES) find "$FLAKE/Nixos" -name '*.nix' 2>/dev/null | wc -l || true ;;
        CONFIG_LOC) find "$FLAKE/Nixos" -name '*.nix' -exec cat {} + 2>/dev/null | wc -l || true ;;
        NIXOS_VERSION) nixos-version 2>/dev/null || true ;;
        KERNEL) uname -r ;;
        HOST) echo "$HOST" ;;
        NIX_VERSION) nix --version 2>/dev/null | awk '{print $3}' || true ;;
        UPTIME) uptime -p 2>/dev/null || true ;;
        BOOT_TIME) systemd-analyze time 2>/dev/null | grep -oE '[0-9.]+s *$' | tr -d ' ' || true ;;
        KERNEL_MODULES) lsmod 2>/dev/null | tail -n +2 | wc -l || true ;;
        SYSTEMD_UNITS) systemctl list-units --all --no-legend 2>/dev/null | wc -l || true ;;
        SYSTEMD_ENABLED) systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | wc -l || true ;;
        SYSTEMD_FAILED) systemctl --failed --no-legend 2>/dev/null | wc -l || true ;;
        GCROOTS) find /nix/var/nix/gcroots -maxdepth 3 2>/dev/null | wc -l || true ;;
        DISK_FREE) df -h /nix 2>/dev/null | awk 'NR==2{print $4}' || true ;;
        DISK_USED_PCT) df -h /nix 2>/dev/null | awk 'NR==2{print $5}' || true ;;
        NIX_FS) findmnt -no FSTYPE,SOURCE /nix 2>/dev/null || true ;;
        *) echo "unknown field: $1" >&2; return 1 ;;
    esac
}

selected=("${field_names[@]}")
mode="labels"   # labels | noheadings | pairs

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--output)
            arg="${2:-}"
            if [ "$arg" = "list" ] || [ "$arg" = "help" ]; then
                prev_cat=""
                for f in "${field_names[@]}"; do
                    cat="$(field_category "$f")"
                    [ "$cat" != "$prev_cat" ] && { echo; echo "-- $cat --"; prev_cat="$cat"; }
                    printf "%-20s %s\n" "$f" "$(field_desc "$f")"
                done
                exit 0
            fi
            IFS=',' read -r -a selected <<< "${arg^^}"
            shift 2
            ;;
        -n|--noheadings) mode="noheadings"; shift ;;
        -p|--pairs) mode="pairs"; shift ;;
        -l|--list)
            prev_cat=""
            for f in "${field_names[@]}"; do
                cat="$(field_category "$f")"
                [ "$cat" != "$prev_cat" ] && { echo; echo "-- $cat --"; prev_cat="$cat"; }
                printf "%-20s %s\n" "$f" "$(field_desc "$f")"
            done
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

prev_cat=""
for f in "${selected[@]}"; do
    value="$(field_value "$f")"
    case "$mode" in
        labels)
            cat="$(field_category "$f")"
            [ "$cat" != "$prev_cat" ] && { [ -n "$prev_cat" ] && echo; echo "-- $cat --"; prev_cat="$cat"; }
            printf "%-20s %s\n" "${f}:" "$value"
            ;;
        noheadings) printf "%s\n" "$value" ;;
        pairs) printf '%s="%s"\n' "$f" "$value" ;;
    esac
done
