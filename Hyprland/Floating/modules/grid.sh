#!/usr/bin/env bash
# modules/grid.sh — fill monitor with equal-area windows, each as square as possible

snap_grid() {
    local gap_pct="${WINDOW_GAP_PCT:-3}"

    hyprctl activewindow -j | python3 -c "
import sys, json, subprocess, math

gap_pct      = ${gap_pct}
max_windows  = int('${MAX_GRID_WINDOWS:-8}')

active   = json.loads(subprocess.check_output(['hyprctl', 'activewindow', '-j']))
mon_id   = active.get('monitor', 0)
ws_id    = active['workspace']['id']

monitors = json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j']))
mon      = next(m for m in monitors if m.get('id') == mon_id)
rx       = mon.get('reserved', [0,0,0,0])
mon_x    = mon['x'] + rx[0]
mon_y    = mon['y'] + rx[1]
mon_w    = mon['width']  - rx[0] - rx[2]
mon_h    = mon['height'] - rx[1] - rx[3]

gap = (min(mon_w, mon_h) * gap_pct) // 100
gap += gap % 2  # round up to even so gap//2 splits exactly

clients = json.loads(subprocess.check_output(['hyprctl', 'clients', '-j']))
windows = [c for c in clients
           if c.get('monitor') == mon_id
           and c['workspace']['id'] == ws_id
           and c.get('floating')
           and not c.get('hidden')]

n = len(windows)
if n == 0:
    print('[hyprfloat] No floating windows on active workspace.')
    sys.exit(0)
if n > max_windows:
    print(f'[hyprfloat] {n} windows exceeds MAX_GRID_WINDOWS={max_windows} — skipping.')
    sys.exit(0)

cache = {}
def best_score(w, h, n):
    key = (w, h, n)
    if key in cache: return cache[key]
    if n == 1:
        r = max(w/h, h/w)
        cache[key] = r; return r
    best = float('inf')
    for left in range(1, n):
        sw_i = round(w * left / n); rw_i = w - sw_i
        sh_i = round(h * left / n); rh_i = h - sh_i
        sv = max(best_score(sw_i, h, left), best_score(rw_i, h, n-left))
        sh = max(best_score(w, sh_i, left), best_score(w, rh_i, n-left))
        best = min(best, sv, sh)
    cache[key] = best; return best

def split(x, y, w, h, n):
    if n == 1:
        return [(x, y, w, h)]
    best_val = float('inf')
    best_cut = None
    for left in range(1, n):
        right = n - left
        sw_i = round(w * left / n); rw_i = w - sw_i
        sh_i = round(h * left / n); rh_i = h - sh_i
        sv = max(best_score(sw_i, h, left), best_score(rw_i, h, right))
        sh = max(best_score(w, sh_i, left), best_score(w, rh_i, right))
        if sv < best_val: best_val = sv; best_cut = ('v', left, right, sw_i, rw_i)
        if sh < best_val: best_val = sh; best_cut = ('h', left, right, sh_i, rh_i)
    axis, left, right, s1, s2 = best_cut
    if axis == 'v':
        return split(x,    y, s1, h,  left) + split(x+s1, y, s2, h,  right)
    else:
        return split(x, y,    w, s1,  left) + split(x, y+s1, w, s2,  right)

hg = gap // 2
rg = gap - hg  # hg + rg = gap exactly even for odd values
inner_x = mon_x + hg
inner_y = mon_y + hg
inner_w = mon_w - gap
inner_h = mon_h - gap
slots = split(inner_x, inner_y, inner_w, inner_h, n)

for win, (sx, sy, sw, sh) in zip(windows, slots):
    wx = sx + hg
    wy = sy + hg
    ww = sw - gap
    wh = sh - gap
    a  = win['address']
    subprocess.run(['hyprctl', 'dispatch', 'resizewindowpixel', f'exact {ww} {wh}, address:{a}'])
    subprocess.run(['hyprctl', 'dispatch', 'movewindowpixel',  f'exact {wx} {wy}, address:{a}'])

print(f'[hyprfloat] Tiled {n} windows (equal area)')
"
}
