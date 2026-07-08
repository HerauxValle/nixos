#!/usr/bin/env bash
# modules/status.sh — report current hyprfloat state

show_status() {
    if [ -f "$STATE_FILE" ]; then
        echo "float mode: ON"
        echo "state file: $STATE_FILE"
    else
        echo "float mode: OFF"
        echo "state file: $STATE_FILE (absent)"
    fi

    echo ""
    echo "config:"
    echo "  WINDOW_GAP_PCT=${WINDOW_GAP_PCT:-3}%"
    echo "  STATE_FILE_DIR=${STATE_FILE_DIR:-/tmp}"
    echo "  STATE_FILE_NAME=${STATE_FILE_NAME:-hyprfloat_mode}"
    echo "  SCRIPT_DIR=$SCRIPT_DIR"
}
