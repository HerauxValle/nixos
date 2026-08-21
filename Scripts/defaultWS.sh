#!/usr/bin/env bash

# Set all monitors to workspace 1 on startup
# Add this to your Hyprland autostart

# Wait a moment for Hyprland to fully initialize
sleep 0.5

# Get all monitor names
monitors=$(hyprctl monitors -j | jq -r '.[].name')

# Switch each monitor to workspace 1
for monitor in $monitors; do
    hyprctl dispatch focusmonitor "$monitor"
    hyprctl dispatch workspace 5
done

# Focus back to the first monitor
first_monitor=$(hyprctl monitors -j | jq -r '.[0].name')
hyprctl dispatch focusmonitor "$first_monitor"