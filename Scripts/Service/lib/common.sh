#!/usr/bin/env bash
# &desc: "service shared helpers -- self-hosted-<name>[@<sub>].service naming and the <name> argument check every subcommand needs."

# Same prefix logic as Pacnix's own `pacnix logs` (cmd/logs.sh): takes
# just the part you actually think in ("openwebui", "comfyui@sync") and
# adds the self-hosted- prefix + .service suffix. Forgiving about an
# already-typed self-hosted- prefix (doesn't double it). The @<sub> half
# passes straight through untouched either way -- every self-hosted
# service that has subservices (see `systemctl list-unit-files | grep
# self-hosted` -- comfyui@, immich@, ollama@, ...) is a real systemd
# template unit, so "name@sub" is already the exact instance syntax
# systemctl itself expects.
unit_name() {
    local spec="$1"
    case "$spec" in
        self-hosted-*) echo "${spec}.service" ;;
        *) echo "self-hosted-${spec}.service" ;;
    esac
}

require_name() {
    if [ -z "${1:-}" ]; then
        echo "usage: service ${cmd_usage:-<command>} <name>[@<sub>] [--silent] [-l|--literal]" >&2
        exit 1
    fi
}

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; MAGENTA='\033[35m'; RESET='\033[0m'

# Strips --silent and -l/--literal flags out of "$@" (in any position)
# into $SILENT/$LITERAL (0/1) and leaves the rest in the $ARGS array --
# start/stop/restart/fail all take just <name>[@<sub>] [--silent]
# [-l|--literal], so this is shared instead of each one hand-rolling its
# own arg scan. --literal skips unit_name's self-hosted- prefixing, for
# units like qbittorrent.service that come from a native nixpkgs module
# (services.qbittorrent) instead of the self-hosted-<name> convention.
parse_args() {
    SILENT=0
    LITERAL=0
    ARGS=()
    local a
    for a in "$@"; do
        case "$a" in
            --silent) SILENT=1 ;;
            -l | --literal) LITERAL=1 ;;
            *) ARGS+=("$a") ;;
        esac
    done
}

# --silent's counterpart to run_with_spinner: fires "$@" fully detached
# (own subshell, not this script's job table -- survives the script
# exiting, no [1]+ Done noise) and returns immediately instead of
# blocking on it. Same `sudo -v` upfront reasoning -- a password prompt
# from inside the detached subshell would be invisible/unanswerable.
run_silent() {
    local color="$1" msg="$2"
    shift 2
    sudo -v || return $?
    ( "$@" >/dev/null 2>&1 & )
    printf ' %b→ %s (backgrounded)%b\n' "$color" "$msg" "$RESET"
}

# Same spinner as mcli's own lib/common.sh (Scripts/Minecraft) -- kept as
# a separate copy rather than a shared file since these are two
# independent Scripts/ projects, same as everywhere else in this repo.
# Runs "$@" in the background with a spinner in front of $msg and a
# growing/cycling "." ".." "..." trail after it (" <frame> <msg><dots>",
# spinner+text+dots in $color while running). `sudo -v` upfront so a
# password prompt (if the cached ticket already expired) happens cleanly
# before the spinner starts overwriting the line, not interleaved with
# it. Each redraw ends in \033[K (erase to end of line) since the dot
# trail's length changes every frame -- without it, a shorter redraw
# leaves stray characters from the previous, longer one behind.
run_with_spinner() {
    local color="$1" msg="$2"
    shift 2
    sudo -v || return $?

    "$@" &
    local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' dot_frames=("" "." ".." "...") i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r %b%s %s%s%b\033[K' "$color" "${frames:i%${#frames}:1}" "$msg" "${dot_frames[i / 3 % 4]}" "$RESET"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid"
    local status=$?
    tput cnorm 2>/dev/null || true

    if [ "$status" -eq 0 ]; then
        printf '\r %b✓ %s%b\033[K\n' "$GREEN" "$msg" "$RESET"
    else
        printf '\r %b✗ %s%b\033[K\n' "$RED" "$msg" "$RESET"
    fi
    return "$status"
}
