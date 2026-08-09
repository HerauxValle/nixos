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
