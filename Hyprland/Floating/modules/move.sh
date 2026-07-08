#!/usr/bin/env bash
# modules/move.sh — snap and resize the active floating window
# Requires: WINDOW_GAP_PCT, DEFAULT_WIDTH_PCT, DEFAULT_HEIGHT_PCT, STATE_FILE_DIR

# Position state file: one line per window — "address:position"
_pos_file() { echo "${STATE_FILE_DIR:-/tmp}/hyprfloat_pos"; }

_get_pos() {
    local addr="$1"
    local f; f="$(_pos_file)"
    [ -f "$f" ] && grep "^${addr}:" "$f" | cut -d: -f2 || echo "unknown"
}

_set_pos() {
    local addr="$1" pos="$2"
    local f; f="$(_pos_file)"
    local tmp; tmp="${f}.tmp"
    if [ -f "$f" ]; then
        grep -v "^${addr}:" "$f" > "$tmp" || true
    fi
    echo "${addr}:${pos}" >> "$tmp"
    mv "$tmp" "$f"
}

_get_monitor_geometry() {
    hyprctl activewindow -j | python3 -c "
import sys, json, subprocess
win = json.load(sys.stdin)
mon_id = win.get('monitor', 0)
monitors = json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j']))
mon = next((m for m in monitors if m.get('id') == mon_id), monitors[0])
rx = mon.get('reserved', [0,0,0,0])
print(mon['x'] + rx[0], mon['y'] + rx[1], mon['width'] - rx[0] - rx[2], mon['height'] - rx[1] - rx[3])
"
}

_get_addr() {
    hyprctl activewindow -j | python3 -c "import sys,json; print(json.load(sys.stdin)['address'])"
}

_resize_and_move() {
    local x="$1" y="$2" w="$3" h="$4" addr="$5"
    if [[ "${HF_LANG_MODE:-false}" == "true" ]]; then
        hyprctl dispatch resizewindowpixel "exact ${w} ${h}, address:${addr}" >/dev/null
        hyprctl dispatch movewindowpixel  "exact ${x} ${y}, address:${addr}" >/dev/null
    else
        hyprctl eval "hl.dispatch(hl.dsp.window.resize({ x = ${w}, y = ${h}, relative = false, window = 'address:${addr}' }))" >/dev/null
        hyprctl eval "hl.dispatch(hl.dsp.window.move({ x = ${x}, y = ${y}, relative = false, window = 'address:${addr}' }))" >/dev/null
    fi
}

_snap_to() {
    local pos="$1"
    local gap_pct="${WINDOW_GAP_PCT:-3}"

    read -r mon_x mon_y mon_w mon_h < <(_get_monitor_geometry)
    local addr; addr="$(_get_addr)"
    local gap=$(( (mon_w < mon_h ? mon_w : mon_h) * gap_pct / 100 ))

    # half dimensions (for sides and corners)
    local hw=$(( (mon_w - gap * 3) / 2 ))
    local hh=$(( (mon_h - gap * 3) / 2 ))
    # full dimensions minus gap
    local fw=$(( mon_w - gap * 2 ))
    local fh=$(( mon_h - gap * 2 ))

    local x y w h

    case "$pos" in
        left)         x=$(( mon_x + gap ))              ; y=$(( mon_y + gap ))              ; w=$hw ; h=$fh ;;
        right)        x=$(( mon_x + mon_w - hw - gap )) ; y=$(( mon_y + gap ))              ; w=$hw ; h=$fh ;;
        top)          x=$(( mon_x + gap ))              ; y=$(( mon_y + gap ))              ; w=$fw ; h=$hh ;;
        bottom)       x=$(( mon_x + gap ))              ; y=$(( mon_y + mon_h - hh - gap )) ; w=$fw ; h=$hh ;;
        top-left)     x=$(( mon_x + gap ))              ; y=$(( mon_y + gap ))              ; w=$hw ; h=$hh ;;
        top-right)    x=$(( mon_x + mon_w - hw - gap )) ; y=$(( mon_y + gap ))              ; w=$hw ; h=$hh ;;
        bottom-left)  x=$(( mon_x + gap ))              ; y=$(( mon_y + mon_h - hh - gap )) ; w=$hw ; h=$hh ;;
        bottom-right) x=$(( mon_x + mon_w - hw - gap )) ; y=$(( mon_y + mon_h - hh - gap )) ; w=$hw ; h=$hh ;;
        fullscreen)   x=$(( mon_x + gap ))              ; y=$(( mon_y + gap ))              ; w=$fw ; h=$fh ;;
        center)
            local cw=$(( mon_w * ${DEFAULT_WIDTH_PCT:-60} / 100 ))
            local ch=$(( mon_h * ${DEFAULT_HEIGHT_PCT:-60} / 100 ))
            x=$(( mon_x + (mon_w - cw) / 2 ))
            y=$(( mon_y + (mon_h - ch) / 2 ))
            w=$cw ; h=$ch
            ;;
        *) echo "[hyprfloat] Unknown position: $pos" >&2; return 1 ;;
    esac

    _resize_and_move "$x" "$y" "$w" "$h" "$addr"
    _set_pos "$addr" "$pos"
    notify_user "Hyprfloat" "$pos" "low"
}

# Transition table: TRANSITIONS[current:direction] = next_position
declare -A TRANSITIONS=(
    # from left
    [left:right]=center      [left:up]=top-left      [left:down]=bottom-left
    # from right
    [right:left]=center      [right:up]=top-right    [right:down]=bottom-right
    # from top
    [top:down]=center        [top:left]=top-left     [top:right]=top-right
    # from bottom
    [bottom:up]=center       [bottom:left]=bottom-left [bottom:right]=bottom-right
    # from top-left
    [top-left:right]=top     [top-left:down]=left
    # from top-right
    [top-right:left]=top     [top-right:down]=right
    # from bottom-left
    [bottom-left:right]=bottom [bottom-left:up]=left
    # from bottom-right
    [bottom-right:left]=bottom [bottom-right:up]=right
    # from fullscreen — break out to sides
    [fullscreen:left]=left   [fullscreen:right]=right [fullscreen:up]=top [fullscreen:down]=bottom
    # from center — treat like fullscreen for navigation
    [center:left]=left       [center:right]=right     [center:up]=top     [center:down]=bottom
)

snap_dir() {
    local dir="$1"   # left | right | up | down
    local addr; addr="$(_get_addr)"
    local cur; cur="$(_get_pos "$addr")"
    local key="${cur}:${dir}"
    local next="${TRANSITIONS[$key]:-}"

    if [ -z "$next" ]; then
        # unknown/untracked position — treat as direct snap
        case "$dir" in
            left)  next=left   ;;
            right) next=right  ;;
            up)    next=top    ;;
            down)  next=bottom ;;
        esac
    fi

    _snap_to "$next"
}

snap_fullscreen() { _snap_to fullscreen; }
snap_center()     { _snap_to center;     }
