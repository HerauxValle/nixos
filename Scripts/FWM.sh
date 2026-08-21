#!/usr/bin/env bash

STATE_FILE="/tmp/hypr_float_mode"

if [ -f "$STATE_FILE" ]; then
    hyprctl keyword windowrule "float off, match:class (.*)" >/dev/null 2>&1
    rm "$STATE_FILE"
    echo "Floating mode: OFF"
    notify-send "Hyprland" "Floating mode OFF"
else
    hyprctl keyword windowrule "float on, match:class (.*)" >/dev/null 2>&1
    touch "$STATE_FILE"
    echo "Floating mode: ON"
    notify-send "Hyprland" "Floating mode ON"
fi