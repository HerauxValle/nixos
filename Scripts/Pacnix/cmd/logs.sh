#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper around journalctl for self-hosted-* units specifically --
# takes just the part you actually think in ("comfyui",
# "comfyui@update:deps:apply") and adds the self-hosted- prefix +
# -u/-f/--no-hostname boilerplate. Forgiving about an already-typed
# self-hosted- prefix (doesn't double it). Anything after the spec is
# passed straight through to journalctl (-n 50, --since, ...).

spec="${1:-}"
if [ -z "$spec" ]; then
    echo "usage: pacnix logs <service>[@<action>] [journalctl-args...]" >&2
    echo "e.g. pacnix logs comfyui" >&2
    echo "     pacnix logs comfyui@sync" >&2
    echo "     pacnix logs comfyui@update:deps:apply" >&2
    exit 1
fi
shift || true

case "$spec" in
    self-hosted-*) unit="${spec}.service" ;;
    *) unit="self-hosted-${spec}.service" ;;
esac

exec journalctl -u "$unit" --no-hostname -f "$@"
