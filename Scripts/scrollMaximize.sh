#!/usr/bin/env bash
# scrollMaximize.sh -- maximize toggle for mainMod+F under Hyprland's
# scrolling (PaperWM-style) layout.
#
# Native "maximized" fullscreen mode's toggle is broken specifically under
# scrolling layout: dispatching it resizes the window on the first call,
# but the compositor's internal fullscreen state never registers the
# change, so neither a second native toggle nor a manual state re-check
# can tell it needs to unset anything. The same dispatcher works correctly
# under dwindle/master, so this only takes over when scrolling is the
# active layout, and defers to the native toggle otherwise.
#
# This is a pure width resize on the still-tiled window -- no floating at
# all, so it stays a completely normal column: movable, swappable, every
# other bind keeps working. Confirmed live: resizing a tiled window's
# width (without floating it first) is respected and not fought by the
# layout engine, and the scrolling layout automatically reflows every
# sibling column's position to make room, pushing whichever ones were
# already left/right further off that same side -- no manual sibling
# handling needed. Height is left untouched since a horizontal-only
# scrolling layout already keeps every column's Y/height reserved-area-
# aware (clears the bar, etc.) regardless of width.
#
# Runs as a plain exec_cmd-bound script rather than an inline Lua function
# bind: hl.bind(keys, function() ... end) was confirmed dead on a real
# keypress (registered, no errors, but zero effect), while the exact same
# logic worked every time invoked manually. Dispatcher-style binds
# (exec_cmd included) are proven to fire, so the state/logic lives here
# instead -- same pattern already used by FWM.sh, cycleMode.sh, and
# hyprfloat elsewhere in this repo.

set -euo pipefail

STATE_FILE="/tmp/hypr_scroll_maximize_widths"

# This Hyprland build parses `hyprctl dispatch <arg>` as a Lua expression
# unconditionally (auto-wrapped in hl.dispatch(...)) -- confirmed live, the
# legacy "DISPATCHER argstring" form errors out here. So every dispatch
# below passes a full hl.dsp.* Lua call as a string, not the legacy syntax
# Floating/modules/move.sh uses in its non---lang branch.

layout=$(hyprctl getoption general:layout -j | python3 -c "import json,sys; print(json.load(sys.stdin)['str'])")
if [ "$layout" != "scrolling" ]; then
    hyprctl dispatch "hl.dsp.window.fullscreen({ mode = 'maximized', action = 'toggle' })"
    exit 0
fi

win_json=$(hyprctl activewindow -j)
addr=$(echo "$win_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['address'])")
height=$(echo "$win_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['size'][1])")

saved_width=$(grep "^${addr}:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 || true)

if [ -n "$saved_width" ]; then
    hyprctl dispatch "hl.dsp.window.resize({ x = ${saved_width}, y = ${height}, relative = false, window = 'address:${addr}' })"
    if [ -f "$STATE_FILE" ]; then
        grep -v "^${addr}:" "$STATE_FILE" > "${STATE_FILE}.tmp" || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
    exit 0
fi

width=$(echo "$win_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['size'][0])")
mon_id=$(echo "$win_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['monitor'])")
mon_width=$(hyprctl monitors -j | python3 -c "import json,sys; d=json.load(sys.stdin); print(next(m['width'] for m in d if m['id'] == $mon_id))")

# general:gaps_out's "css" field is "<top> <right> <bottom> <left>" --
# standard CSS box-model shorthand order.
read -r _ gap_right _ gap_left < <(hyprctl getoption general:gaps_out -j | python3 -c "import json,sys; print(json.load(sys.stdin)['css'])")

echo "${addr}:${width}" >> "$STATE_FILE"
hyprctl dispatch "hl.dsp.window.resize({ x = $((mon_width - gap_left - gap_right)), y = ${height}, relative = false, window = 'address:${addr}' })"
