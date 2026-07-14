#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if ! awww query > /dev/null 2>&1; then
    awww-daemon &
    sleep 0.5
fi

if [[ $# -eq 0 ]]; then
    WALLPAPER="$(find "$SCRIPT_DIR" -maxdepth 1 -type f \( \
        -iname "*.png" -o \
        -iname "*.jpg" -o \
        -iname "*.jpeg" -o \
        -iname "*.webp" -o \
        -iname "*.bmp" -o \
        -iname "*.gif" -o \
        -iname "*.tif" -o \
        -iname "*.tiff" -o \
        -iname "*.avif" \) | head -n1)"

    awww img "$WALLPAPER" \
        --transition-type grow \
        --transition-pos top-right \
        --transition-duration 2
else
    WALLPAPER="$(find "$SCRIPT_DIR" -maxdepth 1 -type f \( \
        -iname "$1.png" -o \
        -iname "$1.jpg" -o \
        -iname "$1.jpeg" -o \
        -iname "$1.webp" -o \
        -iname "$1.bmp" -o \
        -iname "$1.gif" -o \
        -iname "$1.tif" -o \
        -iname "$1.tiff" -o \
        -iname "$1.avif" \) | head -n1)"

    [[ -n "$WALLPAPER" ]] || {
        echo "Wallpaper '$1' not found." >&2
        exit 1
    }

    awww img "$WALLPAPER" \
        --transition-type grow \
        --transition-pos top-right \
        --transition-duration 2
fi
