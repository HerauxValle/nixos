#!/usr/bin/env bash
# modules/notify.sh — thin wrapper around notify-send
# Usage: notify_user "Title" "Message" [urgency: low|normal|critical]

notify_user() {
    local title="${1:-hyprfloat}"
    local message="${2:-}"
    local urgency="${3:-normal}"

    if command -v notify-send &>/dev/null; then
        notify-send --urgency="$urgency" "$title" "$message"
    fi

    # Always echo to stdout so it's useful even without a notification daemon
    echo "[hyprfloat] ${title}: ${message}"
}