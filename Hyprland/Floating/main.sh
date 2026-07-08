#!/usr/bin/env bash
# main.sh — hyprfloat entrypoint
# Usage: main.sh [FLAGS]
#
# Flags:
#   --toggle                 Toggle global float mode on/off
#   --enable                 Enable global float mode
#   --disable                Disable global float mode
#   --side:left|right|top|bottom
#                            Snap active window to that screen edge
#   --corner:top-left|top-right|bottom-left|bottom-right
#                            Snap active window to that corner
#   --center                 Center active window on screen
#   --gap <px>               Override WINDOW_GAP for this invocation
#   --help                   Show this help

set -euo pipefail

# ── Resolve script location (no hardcoded paths) ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"

# ── Load config ──────────────────────────────────────────────────────────────
CONFIG_FILE="${SCRIPT_DIR}/config/defaults.conf"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=config/defaults.conf
    source "$CONFIG_FILE"
fi

# Build STATE_FILE path from config values (never hardcoded)
STATE_FILE="${STATE_FILE_DIR:-/tmp}/${STATE_FILE_NAME:-hyprfloat_mode}"

# ── Load modules ─────────────────────────────────────────────────────────────
source "${SCRIPT_DIR}/modules/notify.sh"
source "${SCRIPT_DIR}/modules/toggle.sh"
source "${SCRIPT_DIR}/modules/move.sh"
source "${SCRIPT_DIR}/modules/conflicts.sh"
source "${SCRIPT_DIR}/modules/status.sh"
source "${SCRIPT_DIR}/modules/grid.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
    cat <<EOF
hyprfloat — floating window manager helper for Hyprland

Usage: $(basename "$0") [FLAG]

Toggle flags:
  --toggle                   Toggle global float mode
  --enable                   Force float mode ON
  --disable                  Force float mode OFF

Snap flags (context-aware — direction depends on current position):
  --dir:left                 Snap/transition left
  --dir:right                Snap/transition right
  --dir:up                   Snap/transition up
  --dir:down                 Snap/transition down
  --fullscreen               Fill screen with gap
  --center                   Center window on screen
  --grid                     Arrange all floating windows into an equal grid

Diagnostics:
  --status                   Show current float mode state and config
  --conflicts                Check project binds for conflicts with hyprland config
  --hyprconf <path>          Hyprland config path (default: ~/.config/hypr/hyprland.conf)

Options:
  --gap <pct>                Override edge gap % (default: ${WINDOW_GAP_PCT:-3}%)
  --help                     Show this help

Examples:
  $(basename "$0") --toggle
  $(basename "$0") --dir:left
  $(basename "$0") --dir:up --gap 5
EOF
}

if [ $# -eq 0 ]; then
    usage
    exit 0
fi

ACTION=""
GAP_OVERRIDE=""
export HF_LANG_MODE=false  # default: Lua/0.55+ mode; --lang = legacy hyprlang mode

while [[ $# -gt 0 ]]; do
    case "$1" in
        --toggle)       ACTION="toggle"         ;;
        --enable)       ACTION="enable"         ;;
        --disable)      ACTION="disable"        ;;
        --fullscreen)   ACTION="fullscreen"      ;;
        --center)       ACTION="center"         ;;
        --grid)         ACTION="grid"           ;;
        --dir:*)        ACTION="dir:${1#--dir:}"       ;;
        --autostart)    ACTION="autostart"      ;;
        --restore)      ACTION="restore"        ;;
        --status)       ACTION="status"         ;;
        --conflicts)    ACTION="conflicts"      ;;
        --lang)         HF_LANG_MODE=true       ;;
        --hyprconf)
            shift
            HYPRLAND_CONFIG="$1"
            export HYPRLAND_CONFIG
            ;;
        --gap)
            shift
            GAP_OVERRIDE="$1"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "[hyprfloat] Unknown flag: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

# Apply gap override if provided
if [ -n "$GAP_OVERRIDE" ]; then
    WINDOW_GAP_PCT="$GAP_OVERRIDE"
fi

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$ACTION" in
    autostart)
        # Always _float_enable (not float_enable) here: STATE_FILE lives in
        # plain /tmp and survives across Hyprland restarts within the same
        # boot, so on a genuine fresh compositor start it can be a stale
        # leftover from the previous session — but the new compositor has
        # no windowrule applied yet regardless of what that marker says.
        [[ "${AUTOSTART:-false}" == "true" ]] && _float_enable || true
        ;;
    restore)
        # re-apply windowrule after config reload based on current state
        if [ -f "$STATE_FILE" ]; then
            _float_enable
        fi
        ;;
    status)         show_status     ;;
    conflicts)      check_conflicts ;;
    toggle)         float_toggle    ;;
    enable)         float_enable    ;;
    disable)        float_disable   ;;
    grid)           snap_grid       ;;
    fullscreen)     snap_fullscreen ;;
    center)         snap_center     ;;
    dir:*)
        snap_dir "${ACTION#dir:}"
        ;;
    "")
        echo "[hyprfloat] No action specified." >&2
        usage
        exit 1
        ;;
    *)
        echo "[hyprfloat] Unhandled action: $ACTION" >&2
        exit 1
        ;;
esac