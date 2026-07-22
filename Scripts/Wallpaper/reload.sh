#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================

WALLPAPER_DIR="$HOME/.config/hypr/.wallpaper"
DEFAULT_INTERVAL=60
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-cycle.pid"

TRANSITION_TYPE="grow"
TRANSITION_POS="top-right"
TRANSITION_DURATION=2

# ==============================================================================
# Functions
# ==============================================================================

ensure_daemon() {
    if ! awww query >/dev/null 2>&1; then
        awww-daemon &
        sleep 0.5
    fi
}

stop_cycle() {
    if [[ -f "$PIDFILE" ]]; then
        pid=$(<"$PIDFILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
}

list_wallpapers() {
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
        \( \
            -iname "*.png" -o \
            -iname "*.jpg" -o \
            -iname "*.jpeg" -o \
            -iname "*.webp" -o \
            -iname "*.bmp" -o \
            -iname "*.gif" -o \
            -iname "*.tif" -o \
            -iname "*.tiff" -o \
            -iname "*.avif" \
        \) \
        -printf "%f\n" | sort
}

find_default() {
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
        \( \
            -iname "*.png" -o \
            -iname "*.jpg" -o \
            -iname "*.jpeg" -o \
            -iname "*.webp" -o \
            -iname "*.bmp" -o \
            -iname "*.gif" -o \
            -iname "*.tif" -o \
            -iname "*.tiff" -o \
            -iname "*.avif" \
        \) | sort | head -n1
}

find_wallpaper() {
    local name="$1"

    find "$WALLPAPER_DIR" -maxdepth 1 -type f \
        \( \
            -iname "$name.png" -o \
            -iname "$name.jpg" -o \
            -iname "$name.jpeg" -o \
            -iname "$name.webp" -o \
            -iname "$name.bmp" -o \
            -iname "$name.gif" -o \
            -iname "$name.tif" -o \
            -iname "$name.tiff" -o \
            -iname "$name.avif" \
        \) | head -n1
}

set_wallpaper() {
    local wallpaper="$1"

    [[ -f "$wallpaper" ]] || {
        echo "Wallpaper not found."
        exit 1
    }

    awww img "$wallpaper" \
        --transition-type "$TRANSITION_TYPE" \
        --transition-pos "$TRANSITION_POS" \
        --transition-duration "$TRANSITION_DURATION"
}

cycle() {
    local interval="$1"

    while true; do
        mapfile -t wallpapers < <(
            find "$WALLPAPER_DIR" -maxdepth 1 -type f \
                \( \
                    -iname "*.png" -o \
                    -iname "*.jpg" -o \
                    -iname "*.jpeg" -o \
                    -iname "*.webp" -o \
                    -iname "*.bmp" -o \
                    -iname "*.gif" -o \
                    -iname "*.tif" -o \
                    -iname "*.tiff" -o \
                    -iname "*.avif" \
                \) | shuf
        )

        for wp in "${wallpapers[@]}"; do
            set_wallpaper "$wp"
            sleep "$interval"
        done
    done
}

usage() {
    cat <<EOF
Usage:
  wallpaper
  wallpaper --default
  wallpaper <name>
  wallpaper --cycle [seconds]
  wallpaper --list
  wallpaper --dir <directory> [command]

Commands:
  --default        Apply default wallpaper.
  --cycle [sec]    Cycle randomly forever (default ${DEFAULT_INTERVAL}s).
  --list           List wallpapers.
  --dir DIR        Temporarily use another directory.
  <name>           Wallpaper name without extension.
EOF
}

# ==============================================================================
# Parse arguments
# ==============================================================================

ACTION="default"
INTERVAL="$DEFAULT_INTERVAL"
NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            [[ $# -ge 2 ]] || {
                echo "--dir requires a directory."
                exit 1
            }
            WALLPAPER_DIR="$2"
            shift 2
            ;;
        --default)
            ACTION="default"
            shift
            ;;
        --cycle)
            ACTION="cycle"
            if [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]]; then
                INTERVAL="$2"
                shift 2
            else
                shift
            fi
            ;;
        --list)
            ACTION="list"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            ACTION="name"
            NAME="$1"
            shift
            ;;
    esac
done

# ==============================================================================
# Execute
# ==============================================================================

ensure_daemon

case "$ACTION" in
    list)
        list_wallpapers
        ;;

    cycle)
        stop_cycle
        cycle "$INTERVAL" &
        echo $! >"$PIDFILE"
        disown
        ;;

    default)
        stop_cycle
        wp="$(find_default)"

        [[ -n "$wp" ]] || {
            echo "No wallpapers found."
            exit 1
        }

        set_wallpaper "$wp"
        ;;

    name)
        stop_cycle
        wp="$(find_wallpaper "$NAME")"

        [[ -n "$wp" ]] || {
            echo "Wallpaper '$NAME' not found."
            exit 1
        }

        set_wallpaper "$wp"
        ;;
esac
