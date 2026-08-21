#!/usr/bin/env python3
"""
Fastfetch config + theme color generator. Run manually, live, whenever you
want to refresh the theme (e.g. after switching distros) -- writes straight
into Dotfiles/Fastfetch/, a normal writable directory, not the Nix store. A
rebuild afterward copies that into ~/.config/fastfetch/ the same way
Hyprland/Kitty/Quickshell are, making it reproducible and rollback-safe from
that point on. Not run automatically at shell startup -- deliberately a
manual step, so the generated files are real, git-tracked dotfiles rather
than a live-regenerated cache. Must be run from this file's actual location
in the Dotfiles checkout (not the ~/.config/scripts symlinked copy) for the
relative path below to reach the real, writable Fastfetch/ directory.
"""
import subprocess, re, os, sys, tempfile, json
from pathlib import Path

HOME          = Path.home()
SCRIPT_DIR    = Path(__file__).resolve().parent   # Scripts/Reload
FASTFETCH_DIR = SCRIPT_DIR.parent.parent / 'Fastfetch'   # -> Dotfiles/Fastfetch
CONFIG_OUT    = FASTFETCH_DIR / 'config.jsonc'
# Plain KEY=value text, not shell syntax -- whatever reads this parses it
# however it wants, instead of only being sourceable by one specific shell.
THEME_CACHE   = FASTFETCH_DIR / 'colors.env'

ICONS = {
    'os':       '\U000f0e56', 'host':     '\U000f01c4',
    'kernel':   '\U000f030a', 'uptime':   '\U000f051f',
    'packages': '\U000f03d7', 'shell':    '\U000f0489',
    'wm':       '\U000f10ac', 'terminal': '\U000f0120',
    'cpu':      '\U000f04bc', 'gpu':      '\U000f0678',
    'memory':   '\U000f035b', 'disk':     '\U000f02ca',
    'localip':  '\U000f05a9', 'colors':   '\U000f043e',
    'arch':     '\U000f0e56',
}

LOGO_PADDING       = {"left": 6, "top": 2, "right": 6, "bottom": 0}
BOTTOM_BLANK_LINES = 2


def hex_to_256(hexcolor: str) -> int:
    """Nearest xterm-256 color index for a 6-digit hex string (no '#')."""
    r, g, b = int(hexcolor[0:2], 16), int(hexcolor[2:4], 16), int(hexcolor[4:6], 16)
    steps = [0, 95, 135, 175, 215, 255]
    def nearest_step(v): return min(range(6), key=lambda i: abs(steps[i] - v))
    ri, gi, bi = nearest_step(r), nearest_step(g), nearest_step(b)
    cube_color = 16 + 36 * ri + 6 * gi + bi
    cr, cg, cb = steps[ri], steps[gi], steps[bi]
    cube_dist = (cr - r) ** 2 + (cg - g) ** 2 + (cb - b) ** 2
    gray_idx = round((r + g + b) / 3)
    gray_level = min(23, max(0, round((gray_idx - 8) / 10)))
    gray_val = 8 + gray_level * 10
    gray_color = 232 + gray_level
    gray_dist = (gray_val - r) ** 2 + (gray_val - g) ** 2 + (gray_val - b) ** 2
    return cube_color if cube_dist <= gray_dist else gray_color


# Primary/contrast color per distro, as plain hex (no '#') -- this is the one
# canonical representation; fastfetch's own "38;5;N" 256-color codes are
# derived from it at generation time via hex_to_256(). Keyed by
# /etc/os-release's ID field (the standard, distro-agnostic way to identify
# what's running -- nothing here is Nix-specific detection logic). Falls back
# to "arch" if the running distro has no theme defined below.
THEMES = {
    "arch":  {"primary": "D78787", "contrast": "87AF87"},  # salmon/rose + sage green
    "nixos": {"primary": "87AFD7", "contrast": "AFAFAF"},  # logo blue + logo gray

    # everything below: real brand-color primary + a programmatically
    # computed complementary-hue contrast, not hand-picked/eyeballed on
    # that distro -- treat as a starting point to tweak once someone has.
    "ubuntu":               {"primary": "E95420", "contrast": "20B5E9"},  # not tested
    "debian":               {"primary": "A81D33", "contrast": "1DA892"},  # not tested
    "fedora":               {"primary": "3C6EB4", "contrast": "B4823C"},  # not tested
    "linuxmint":            {"primary": "87CF3E", "contrast": "863ECF"},  # not tested
    "opensuse-tumbleweed":  {"primary": "73BA25", "contrast": "6C25BA"},  # not tested
    "manjaro":              {"primary": "35BF5C", "contrast": "BF3598"},  # not tested
    "gentoo":               {"primary": "54487A", "contrast": "6E7A48"},  # not tested
    "slackware":            {"primary": "4E5DA1", "contrast": "A1924E"},  # not tested
    "centos":               {"primary": "932279", "contrast": "22933C"},  # not tested
    "rhel":                 {"primary": "EE0000", "contrast": "00EEEE"},  # not tested
    "kali":                 {"primary": "557C94", "contrast": "946D55"},  # not tested
    "void":                 {"primary": "295239", "contrast": "522942"},  # not tested
    "alpine":               {"primary": "0D597F", "contrast": "7F330D"},  # not tested
    "elementary":           {"primary": "64BAFF", "contrast": "FFA964"},  # not tested
    "zorin":                {"primary": "0CC1F3", "contrast": "F33E0C"},  # not tested
    "pop":                  {"primary": "48B9C7", "contrast": "C75648"},  # not tested
    "mx":                   {"primary": "4F9A8D", "contrast": "9A4F5C"},  # not tested
    "deepin":               {"primary": "2CA6F0", "contrast": "F0762C"},  # not tested
    "solus":                {"primary": "5294E2", "contrast": "E2A052"},  # not tested
    "endeavouros":          {"primary": "7F3FBF", "contrast": "7FBF3F"},  # not tested

    # niche but actively maintained (not abandoned/discontinued projects)
    # -- same "not tested" caveat as above, just a longer tail of coverage.
    "artix":                {"primary": "00B39F", "contrast": "B30014"},  # not tested
    "garuda":               {"primary": "A020F0", "contrast": "70F020"},  # not tested
    "cachyos":              {"primary": "00A9E0", "contrast": "E03700"},  # not tested
    "devuan":               {"primary": "8E44AD", "contrast": "63AD44"},  # not tested
    "pureos":               {"primary": "6F42C1", "contrast": "94C142"},  # not tested
    "trisquel":             {"primary": "0060A9", "contrast": "A94900"},  # not tested
    "guix":                 {"primary": "F5C211", "contrast": "1144F5"},  # not tested
    "rocky":                {"primary": "10B981", "contrast": "B91048"},  # not tested
    "almalinux":            {"primary": "0072CE", "contrast": "CE5C00"},  # not tested
    "ol":                   {"primary": "C74634", "contrast": "34B5C7"},  # not tested -- Oracle Linux
    "amzn":                 {"primary": "FF9900", "contrast": "0066FF"},  # not tested -- Amazon Linux
    "steamos":              {"primary": "1B2838", "contrast": "382B1B"},  # not tested
    "bazzite":              {"primary": "9C59D1", "contrast": "8ED159"},  # not tested
    "neon":                 {"primary": "1D99F3", "contrast": "F3771D"},  # not tested -- KDE neon
    "chimera":              {"primary": "4DB6AC", "contrast": "B64D57"},  # not tested -- Chimera Linux
    "bedrock":              {"primary": "888888", "contrast": "888888"},  # not tested -- Bedrock Linux
    "tails":                {"primary": "56347C", "contrast": "5A7C34"},  # not tested
    "blackarch":            {"primary": "FF0000", "contrast": "00FFFF"},  # not tested
    "parrot":               {"primary": "12C2E9", "contrast": "E93912"},  # not tested -- Parrot Security OS
    "mageia":               {"primary": "1489CB", "contrast": "CB5614"},  # not tested
    "pclinuxos":            {"primary": "1976D2", "contrast": "D27519"},  # not tested
    "antix":                {"primary": "4A4A4A", "contrast": "4A4A4A"},  # not tested -- antiX
    "4mlinux":              {"primary": "4CAF50", "contrast": "AF4CAB"},  # not tested
    "nutyx":                {"primary": "F57C00", "contrast": "0079F5"},  # not tested
    "salix":                {"primary": "6AAB5A", "contrast": "9B5AAB"},  # not tested
    "kaos":                 {"primary": "7C4DFF", "contrast": "D0FF4D"},  # not tested -- KaOS
    "funtoo":               {"primary": "6A1B9A", "contrast": "4B9A1B"},  # not tested
    "calculate":            {"primary": "009688", "contrast": "96000E"},  # not tested -- Calculate Linux
    "postmarketos":         {"primary": "6DB53F", "contrast": "873FB5"},  # not tested
    "openmandriva":         {"primary": "1197D4", "contrast": "D44E11"},  # not tested
    "rosa":                 {"primary": "1B75BC", "contrast": "BC621B"},  # not tested -- ROSA Linux
    "sparky":               {"primary": "E64A19", "contrast": "19B5E6"},  # not tested -- SparkyLinux
}
DEFAULT_THEME = "arch"


def detect_theme() -> str:
    try:
        os_release = Path('/etc/os-release').read_text()
        m = re.search(r'^ID=(.*)$', os_release, re.MULTILINE)
        distro_id = m.group(1).strip().strip('"') if m else ""
    except Exception as e:
        print(f"  os-release read failed ({e}), theme={DEFAULT_THEME}", file=sys.stderr)
        distro_id = ""
    theme = distro_id if distro_id in THEMES else DEFAULT_THEME
    print(f"  distro_id={distro_id!r} -> theme={theme}", file=sys.stderr)
    return theme


THEME         = THEMES[detect_theme()]
PRIMARY_HEX   = THEME["primary"]
CONTRAST_HEX  = THEME["contrast"]
ACCENT        = f'38;5;{hex_to_256(PRIMARY_HEX)}'
CONTRAST_ANSI = f'38;5;{hex_to_256(CONTRAST_HEX)}'
C       = f'{{#{ACCENT}}}'
C0      = '{#}'
KEY_WIDTH = 8
BOX_WIDTH = 59


def _run_ff(cfg: str) -> bytes:
    with tempfile.NamedTemporaryFile('w', suffix='.jsonc', delete=False) as f:
        f.write(cfg); tmp = f.name
    try:
        return subprocess.run(['fastfetch', '--config', tmp],
                              capture_output=True, timeout=5).stdout
    finally:
        os.unlink(tmp)


def measure_logo_rows() -> int:
    lp = LOGO_PADDING
    cfg = (f'{{"logo":{{"type":"auto","padding":{{"left":{lp["left"]},'
           f'"top":{lp["top"]},"right":{lp["right"]},"bottom":0}}}},"modules":[]}}')
    try:
        rows = len([l for l in _run_ff(cfg).split(b'\n') if l])
        print(f"  logo_rows={rows}", file=sys.stderr)
        return rows
    except Exception as e:
        print(f"  logo measure failed ({e}), fallback=21", file=sys.stderr)
        return 21


def measure_info_col() -> int:
    lp = LOGO_PADDING
    cfg = (f'{{"logo":{{"type":"auto","padding":{{"left":{lp["left"]},'
           f'"top":{lp["top"]},"right":{lp["right"]},"bottom":{lp["bottom"]}}}}},'
           f'"modules":[{{"type":"title","format":"\\u256d"}}]}}')
    try:
        for line in _run_ff(cfg).split(b'\n'):
            clean = re.sub(rb'\x1b\[[^a-zA-Z]*[a-zA-Z]', b'', line)
            if b'\xe2\x95\xad' in clean:
                col = len(clean[:clean.index(b'\xe2\x95\xad')].decode('utf-8', errors='replace')) + 1
                print(f"  info_col={col}", file=sys.stderr)
                return col
    except Exception as e:
        print(f"  info_col measure failed ({e}), fallback=43", file=sys.stderr)
    return 43


def camel_to_kebab(name: str) -> str:
    out = ''
    for ch in name:
        out += ('-' + ch.lower()) if ch.isupper() else ch
    return out


def build_packages_format() -> str:
    """Discovers whatever package managers fastfetch actually detects on this
    machine (via its own structured JSON output) and builds a format string
    from those -- not hardcoded to any one distro/manager. On a pacman system
    this naturally yields "{pacman} (pacman)"; here it yields the nix-system/
    nix-user split. Falls back to the plain {all} count if detection fails."""
    try:
        raw = subprocess.run(['fastfetch', '--format', 'json', '-s', 'packages'],
                              capture_output=True, timeout=5, text=True).stdout
        data = json.loads(raw)[0]['result']
    except Exception as e:
        print(f"  packages format detect failed ({e}), fallback={{all}}", file=sys.stderr)
        return '{all}'

    parts = [
        f'{{{camel_to_kebab(key)}}} ({camel_to_kebab(key)})'
        for key, count in data.items()
        if key != 'all' and count
    ]
    fmt = ', '.join(parts) if parts else '{all}'
    print(f"  packages_format={fmt}", file=sys.stderr)
    return fmt


def main():
    logo_rows = measure_logo_rows()
    info_col  = measure_info_col()
    packages_format = build_packages_format()

    d1 = '─' * (BOX_WIDTH - 34)   # dashes in title after user@host
    d2 = '─' * (BOX_WIDTH - 2)    # dashes in bottom border
    # d3: jump to right border col, print │, return to value start col
    col_right = info_col + BOX_WIDTH - 1
    col_value = info_col + 1 + 1 + KEY_WIDTH + 2  # icon+space+key+separator
    d3 = f'\\u001b[{col_right}G\\u001b[{ACCENT}m│\\u001b[0m\\u001b[{col_value}G'

    def k(label): return label.ljust(KEY_WIDTH)

    colors_key     = f'{C}{ICONS["colors"]} {k("colors")}{C0}  '
    colors_circles = ' '.join(f'{{#{c}}}●{{#}}' for c in [30, 31, 32, 33, 34, 35, 36, 37])
    colors_fmt     = colors_key + '{$3}' + colors_circles

    total_logo_rows  = LOGO_PADDING["top"] + logo_rows
    logo_center      = LOGO_PADDING["top"] + logo_rows / 2
    box_content_rows = 16  # title + 13 data modules + colors + bottom border
    top_blanks       = max(0, round(logo_center - box_content_rows / 2) - 1)
    print(f"  top_blanks={top_blanks}", file=sys.stderr)

    modules = [
        *(['    { "type": "custom", "format": "" }'] * top_blanks),
        f'    {{ "type": "title",    "format": "{C}╭── {ICONS["arch"]}  {{user-name}}@{{host-name}} ──{{$1}}╮{C0}" }}',
        f'    {{ "type": "os",       "keyIcon": "{ICONS["os"]}",       "key": "{k("distro")}",   "format": "{{$3}}{"{pretty-name} {arch}"}" }}',
        f'    {{ "type": "host",     "keyIcon": "{ICONS["host"]}",     "key": "{k("host")}",     "format": "{{$3}}{"{name} ({version})"}" }}',
        f'    {{ "type": "kernel",   "keyIcon": "{ICONS["kernel"]}",   "key": "{k("kernel")}",   "format": "{{$3}}{"{sysname} {release}"}" }}',
        f'    {{ "type": "uptime",   "keyIcon": "{ICONS["uptime"]}",   "key": "{k("uptime")}",   "format": "{{$3}}{"{?days}{days} days, {?}{hours} hours, {minutes} mins"}" }}',
        f'    {{ "type": "packages", "keyIcon": "{ICONS["packages"]}", "key": "{k("packages")}", "format": "{{$3}}{packages_format}" }}',
        f'    {{ "type": "shell",    "keyIcon": "{ICONS["shell"]}",    "key": "{k("shell")}",    "format": "{{$3}}{"{pretty-name} {version}"}" }}',
        f'    {{ "type": "wm",       "keyIcon": "{ICONS["wm"]}",       "key": "{k("wm")}",       "format": "{{$3}}{"{pretty-name} {version} ({protocol-name})"}" }}',
        f'    {{ "type": "terminal", "keyIcon": "{ICONS["terminal"]}", "key": "{k("term")}",     "format": "{{$3}}{"{pretty-name}{?version} {version}{?}"}" }}',
        f'    {{ "type": "cpu",      "keyIcon": "{ICONS["cpu"]}",      "key": "{k("cpu")}",      "format": "{{$3}}{"{cores-physical}C/{cores-logical}T  {name}"}" }}',
        f'    {{ "type": "gpu",      "keyIcon": "{ICONS["gpu"]}",      "key": "{k("gpu")}",      "format": "{{$3}}{"{name}"}" }}',
        f'    {{ "type": "memory",   "keyIcon": "{ICONS["memory"]}",   "key": "{k("memory")}",   "format": "{{$3}}{"{used} / {total} ({percentage})"}" }}',
        f'    {{ "type": "disk",     "keyIcon": "{ICONS["disk"]}",     "key": "{k("disk")}",     "folders": "/", "format": "{{$3}}{"{size-used} / {size-total} ({size-percentage}) - {filesystem}"}" }}',
        f'    {{ "type": "localip",  "keyIcon": "{ICONS["localip"]}",  "key": "{k("local ip")}", "format": "{{$3}}{"{ipv4}"}" }}',
        f'    {{ "type": "custom",   "format": "{colors_fmt}" }}',
        f'    {{ "type": "custom",   "format": "{C}╰{{$2}}╯{C0}" }}',
    ]

    trailing = max(0, total_logo_rows - len(modules) + BOTTOM_BLANK_LINES)
    for _ in range(trailing):
        modules.append('    { "type": "custom", "format": "" }')
    print(f"  trailing_blank={trailing}", file=sys.stderr)

    out  = '{\n'
    out += '  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json",\n'
    lp   = LOGO_PADDING
    out += f'  "logo": {{ "type": "auto", "padding": {{ "left": {lp["left"]}, "top": {lp["top"]}, "right": {lp["right"]}, "bottom": {lp["bottom"]} }} }},\n'
    out += '  "display": {\n'
    out += '    "separator": "  ",\n'
    out += '    "key": { "type": "both" },\n'
    out += f'    "color": {{ "keys": "{ACCENT}" }},\n'
    out += '    "brightColor": false,\n'
    out += f'    "constants": ["{d1}", "{d2}", "{d3}"]\n'
    out += '  },\n'
    out += '  "modules": [\n'
    out += ',\n'.join(modules)
    out += '\n  ]\n}'

    CONFIG_OUT.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_OUT.write_text(out)
    print(f"Written: {CONFIG_OUT}", file=sys.stderr)

    write_theme_cache()
    print(f"Written: {THEME_CACHE}", file=sys.stderr)


def write_theme_cache():
    THEME_CACHE.parent.mkdir(parents=True, exist_ok=True)
    THEME_CACHE.write_text(
        f'PRIMARY_HEX={PRIMARY_HEX}\n'
        f'CONTRAST_HEX={CONTRAST_HEX}\n'
        f'CONTRAST_ANSI={CONTRAST_ANSI}\n'
    )


if __name__ == '__main__':
    # --theme-only skips the three fastfetch subprocess calls main() makes
    # to measure logo/column layout -- just distro-detect + write the color
    # file. Fast enough to run on every shell startup unprompted, so prompt
    # colors are always current without ever needing to run anything by hand.
    if '--theme-only' in sys.argv:
        write_theme_cache()
    else:
        main()
