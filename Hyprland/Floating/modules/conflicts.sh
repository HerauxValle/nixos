#!/usr/bin/env bash
# modules/conflicts.sh -- check hyprfloat keybinds against live hyprland binds

check_conflicts() {
    local project_conf="${SCRIPT_DIR}/hyprland/hyprfloat.conf"

    if [ ! -f "$project_conf" ]; then
        echo "[hyprfloat] ERROR: project config not found at $project_conf" >&2
        return 1
    fi
    if ! command -v hyprctl &>/dev/null; then
        echo "[hyprfloat] ERROR: hyprctl not found -- is Hyprland running?" >&2
        return 1
    fi

    echo "[hyprfloat] Checking project binds against live Hyprland state..."
    echo ""

    local live_json
    live_json="$(hyprctl binds -j)"
    local hypr_conf="${HYPRLAND_CONFIG:-$HOME/.config/hypr/hyprland.conf}"

    python3 - "$project_conf" "$live_json" "$hypr_conf" << 'PYEOF'
import sys, json, re

MOD_BITS = {
    'SHIFT': 1, 'CAPS': 2, 'CTRL': 4, 'CONTROL': 4,
    'ALT': 8, 'MOD2': 16, 'MOD3': 32,
    'SUPER': 64, 'WIN': 64, 'LOGO': 64, 'META': 64,
    'MOD5': 128,
}

def parse_mods(mod_str, variables):
    # resolve hyprland variables like $mainMod -- longest key first to avoid prefix collisions
    for var, val in sorted(variables.items(), key=lambda kv: len(kv[0]), reverse=True):
        mod_str = mod_str.replace(var, val)
    mask = 0
    for token in re.split(r'[\s,]+', mod_str.upper()):
        token = token.strip()
        if token in MOD_BITS:
            mask |= MOD_BITS[token]
    return mask

def collect_variables(root):
    """Recursively follow source= lines from the hyprland config tree,
    collect all $VAR = value definitions. Returns dict {$VAR: value}."""
    variables = {}
    visited = set()
    queue = [os.path.expanduser(root)]
    while queue:
        path = queue.pop(0)
        path = os.path.expanduser(path)
        if not os.path.isfile(path) or path in visited:
            continue
        visited.add(path)
        try:
            with open(path) as f:
                for line in f:
                    stripped = line.strip()
                    # variable definition
                    vm = re.match(r'^\$(\w+)\s*=\s*(.+)', stripped)
                    if vm:
                        variables[f'${vm.group(1)}'] = vm.group(2).strip()
                        continue
                    # source = path (strip inline comments)
                    sm = re.match(r'^source\s*=\s*([^#]+)', stripped)
                    if sm:
                        src = sm.group(1).strip()
                        # resolve variables in source path -- longest key first
                        for var, val in sorted(variables.items(), key=lambda kv: len(kv[0]), reverse=True):
                            src = src.replace(var, val)
                        src = os.path.expanduser(src)
                        queue.append(src)
        except OSError:
            pass
    return variables

def parse_conf(path, seed_vars=None):
    variables = dict(seed_vars or {})
    binds = []
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            # variable assignment local to this file
            vm = re.match(r'^\$(\w+)\s*=\s*(.+)', stripped)
            if vm:
                variables[f'${vm.group(1)}'] = vm.group(2).strip()
                continue
            # bind line
            bm = re.match(r'^bind[a-z]*\s*=\s*([^,]*),\s*([^,]+),\s*([^,]+),?\s*(.*)', stripped, re.I)
            if bm:
                mod_str, key, dispatcher, arg = bm.groups()
                mask = parse_mods(mod_str, variables)
                binds.append({
                    'mask': mask,
                    'key': key.strip().upper(),
                    'dispatcher': dispatcher.strip(),
                    'arg': arg.strip(),
                    'lineno': lineno,
                    'file': path,
                    'raw': stripped,
                })
    return binds

def collect_binds(root, seed_vars=None):
    """Recursively follow source= lines and collect all bind entries with file+line."""
    variables = dict(seed_vars or {})
    binds = []
    visited = set()
    queue = [os.path.expanduser(root)]
    while queue:
        path = queue.pop(0)
        path = os.path.expanduser(path)
        if not os.path.isfile(path) or path in visited:
            continue
        visited.add(path)
        try:
            with open(path) as f:
                for lineno, line in enumerate(f, 1):
                    stripped = line.strip()
                    if not stripped or stripped.startswith('#'):
                        continue
                    vm = re.match(r'^\$(\w+)\s*=\s*(.+)', stripped)
                    if vm:
                        variables[f'${vm.group(1)}'] = vm.group(2).strip()
                        continue
                    sm = re.match(r'^source\s*=\s*([^#]+)', stripped)
                    if sm:
                        src = sm.group(1).strip()
                        for var, val in variables.items():
                            src = src.replace(var, val)
                        queue.append(os.path.expanduser(src))
                        continue
                    bm = re.match(r'^bind[a-z]*\s*=\s*([^,]*),\s*([^,]+),\s*([^,]+),?\s*(.*)', stripped, re.I)
                    if bm:
                        mod_str, key, dispatcher, arg = bm.groups()
                        mask = parse_mods(mod_str, variables)
                        binds.append({
                            'mask': mask,
                            'key': key.strip().upper(),
                            'dispatcher': dispatcher.strip(),
                            'arg': arg.strip(),
                            'lineno': lineno,
                            'file': path,
                            'raw': stripped,
                        })
        except OSError:
            pass
    return binds

import os

# crawl hyprland config tree for variable definitions ($mainMod etc.)
hypr_conf = sys.argv[3] if len(sys.argv) > 3 else os.path.expanduser('~/.config/hypr/hyprland.conf')
global_vars = collect_variables(hypr_conf)

# build live index from config files so we have file+line info
# fall back to raw hyprctl JSON for any bind not found in config (e.g. plugins)
live_binds_json = json.loads(sys.argv[2])
config_binds = collect_binds(hypr_conf, seed_vars=global_vars)
config_index = {}  # (mask, key, dispatcher, arg) → bind entry with file/line
for b in config_binds:
    config_index[(b['mask'], b['key'], b['dispatcher'], b['arg'])] = b

live_index = {}  # (mask, key) → list of bind entries
for b in live_binds_json:
    mask = b.get('modmask', 0)
    key  = b.get('key', '').upper()
    disp = b.get('dispatcher', '')
    arg  = b.get('arg', '')
    entry = config_index.get((mask, key, disp, arg), b)
    live_index.setdefault((mask, key), []).append(entry)

# project binds -- seeded with global vars so $mainMod resolves correctly
conf_path = sys.argv[1]
proj_binds = parse_conf(conf_path, seed_vars=global_vars)

if not proj_binds:
    print("[hyprfloat] No binds found in project config.")
    sys.exit(0)

print(f"[hyprfloat] {len(proj_binds)} project bind(s) vs {len(live_binds_json)} live bind(s)\n")

def flags(arg): return ' '.join(a for a in arg.split() if a.startswith('-'))

conflicts = 0
for pb in proj_binds:
    k = (pb['mask'], pb['key'])
    if k not in live_index:
        continue
    for lb in live_index[k]:
        # skip if this live entry is the project's own bind already loaded
        if lb.get('dispatcher') == pb['dispatcher'] and flags(lb.get('arg','')) == flags(pb.get('arg','')):
            continue
        conflicts += 1
        print(f"⚠  CONFLICT  {pb['key']}  (modmask={pb['mask']})")
        print(f"   project  line {pb['lineno']}: {pb['raw']}")
        if 'file' in lb:
            print(f"   live     {lb['file']}:{lb['lineno']}: {lb['raw']}")
        else:
            print(f"   live     dispatcher={lb.get('dispatcher')}  arg={lb.get('arg')}")
        print()

if conflicts == 0:
    print(f"✓ No conflicts -- all {len(proj_binds)} project binds are clean.")
else:
    print(f"✗ {conflicts} conflict(s) found.")
    sys.exit(1)
PYEOF
}