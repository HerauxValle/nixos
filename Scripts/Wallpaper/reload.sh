#!/usr/bin/env bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
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

if ! awww query > /dev/null 2>&1; then
    awww-daemon &
    sleep 0.5
fi

awww img "$WALLPAPER" --transition-type grow --transition-pos top-right --transition-duration 2
