#!/usr/bin/env bash

# Detect config format
HYPR_DIR="$HOME/.config/hypr"
if [[ -f "$HYPR_DIR/hyprland.lua" ]]; then
    WINDOW_MODE_CONF="$HYPR_DIR/Config/Reactive/windowMode.lua"
    scrolling_CONF="$HYPR_DIR/Config/Plugins/hyprscroll.lua"
    LUA=true
else
    WINDOW_MODE_CONF="$HYPR_DIR/Config/Reactive/windowMode.conf"
    scrolling_CONF="$HYPR_DIR/Config/Plugins/hyprscroll.conf"
    LUA=false
fi

# Get current layout
if $LUA; then
    current=$(awk '/layout\s*=/ { gsub(/.*layout\s*=\s*"/, ""); gsub(/".*/, ""); print; exit }' "$WINDOW_MODE_CONF")
else
    current=$(awk '/^general {/,/^}/ { if (/layout =/) { gsub(/.*layout *= */, ""); gsub(/[ \t]*$/, ""); print; exit } }' "$WINDOW_MODE_CONF")
fi

# Determine next layout
case "$current" in
    dwindle)
        new_layout="scrolling"
        message="Switched to scrolling (PaperWM)"
        ;;
    scrolling)
        new_layout="dwindle"
        message="Switched to dwindle"
        ;;
    *)
        new_layout="dwindle"
        message="Switched to dwindle (default)"
        ;;
esac

# Update layout in file
if $LUA; then
    sed -i "s/layout\s*=\s*\"[^\"]*\"/layout = \"$new_layout\"/" "$WINDOW_MODE_CONF"
else
    sed -i "/^general {/,/^}/ s/^\(\s*layout\s*=\s*\).*/\1$new_layout/" "$WINDOW_MODE_CONF"
fi

# Comment/uncomment section helpers
if $LUA; then
    comment_section() {
        local marker="$1"
        sed -i "/^-- $marker >>/,/^-- << END/ {
            /^--&/b
            /^-- $marker >>/b
            /^-- << END/b
            /^-- /b
            /^[[:space:]]*$/b
            s/^/-- /
        }" "$WINDOW_MODE_CONF"
    }

    uncomment_section() {
        local marker="$1"
        sed -i "/^-- $marker >>/,/^-- << END/ {
            /^--&/b
            /^-- $marker >>/b
            /^-- << END/b
            s/^-- //
        }" "$WINDOW_MODE_CONF"
    }
else
    comment_section() {
        local marker="$1"
        sed -i "/^# $marker >>/,/^# << END/ {
            /^#&/b
            /^# $marker >>/b
            /^# << END/b
            /^# /b
            /^[[:space:]]*$/b
            s/^/# /
        }" "$WINDOW_MODE_CONF"
    }

    uncomment_section() {
        local marker="$1"
        sed -i "/^# $marker >>/,/^# << END/ {
            /^#&/b
            /^# $marker >>/b
            /^# << END/b
            s/^# //
        }" "$WINDOW_MODE_CONF"
    }
fi

# Manage binds
case "$new_layout" in
    dwindle)
        uncomment_section "Dwindle"
        comment_section "Hyprscroll"
        ;;
    scrolling)
        comment_section "Dwindle"
        uncomment_section "Hyprscroll"

        if $LUA; then
            sed -i 's/column_width\s*=\s*[0-9.]*/column_width = 0.5/' "$scrolling_CONF"
        else
            sed -i 's/^\(\s*column_default_width\s*=\s*\).*/\1onehalf/' "$scrolling_CONF"
        fi
        ;;
esac

# Apply immediately + reload so new binds take effect
hyprctl keyword general:layout "$new_layout"
hyprctl reload
notify-send "Layout" "$message"
