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
        echo "usage: service ${cmd_usage:-<command>} <name>[@<sub>]" >&2
        exit 1
    fi
}

# Same spinner as mcli's own lib/common.sh (Scripts/Minecraft) -- kept as
# a separate copy rather than a shared file since these are two
# independent Scripts/ projects, same as everywhere else in this repo.
# `sudo -v` upfront so a password prompt (if the cached ticket already
# expired) happens cleanly before the spinner starts overwriting the
# line, not interleaved with it.
run_with_spinner() {
    local msg="$1"
    shift
    sudo -v || return $?

    "$@" &
    local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%s %s' "$msg" "${frames:i%${#frames}:1}"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid"
    local status=$?
    tput cnorm 2>/dev/null || true

    if [ "$status" -eq 0 ]; then
        printf '\r%s done ✓\n' "$msg"
    else
        printf '\r%s failed ✗\n' "$msg"
    fi
    return "$status"
}
