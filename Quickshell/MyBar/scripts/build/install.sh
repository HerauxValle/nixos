#!/usr/bin/env bash
# install.sh — compile binaries and install missing runtime dependencies.
#
# Dependency state is saved to ~/.config/mybar/state/pkgs.json so that
# uninstall.sh only removes packages that were NOT already installed.

set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STATE_DIR="$HOME/.config/mybar/state"
PKG_STATE="$STATE_DIR/pkgs.json"

mkdir -p "$STATE_DIR"

# ── 1. Compile ────────────────────────────────────────────────────────────────
echo "[install] Compiling binaries..."
bash "$DIR/scripts/build/compile.sh"

# ── 2. Detect package manager ─────────────────────────────────────────────────
detect_pm() {
    if   command -v pacman  &>/dev/null; then echo "pacman"
    elif command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf     &>/dev/null; then echo "dnf"
    elif command -v zypper  &>/dev/null; then echo "zypper"
    else echo ""
    fi
}

PM=$(detect_pm)
if [ -z "$PM" ]; then
    echo "[install] WARNING: No supported package manager found (pacman/apt/dnf/zypper)."
    echo "[install] Install dependencies manually:"
    echo "  networkmanager, bluez, bluez-utils, pipewire, wireplumber,"
    echo "  libnotify, networkmanager-libs, qt6-base, g++, pkg-config"
    exit 0
fi
echo "[install] Package manager: $PM"

# ── 3. Package name map per distro ────────────────────────────────────────────
# Format: "label:check_binary_or_file|pacman_pkg|apt_pkg|dnf_pkg|zypper_pkg"
# check: "bin:NAME" = which NAME, "lib:PATH" = test -f PATH, "pkg:NAME" = pkg query

declare -a DEPS=(
    # label          | check              | pacman              | apt                      | dnf                        | zypper
    "networkmanager  | bin:nmcli          | networkmanager      | network-manager           | NetworkManager             | NetworkManager"
    "bluez           | bin:bluetoothctl   | bluez               | bluez                    | bluez                      | bluez"
    "bluez-utils     | bin:bluetoothctl   | bluez-utils         | bluez                    | bluez                      | bluez"
    "pipewire        | bin:wpctl          | pipewire            | pipewire                 | pipewire                   | pipewire"
    "wireplumber     | bin:wpctl          | wireplumber         | wireplumber              | wireplumber                | wireplumber"
    "libnotify       | bin:notify-send    | libnotify           | libnotify-bin            | libnotify                  | libnotify-tools"
    "networkmanager-libnm | lib:/usr/lib/libnm.so.0 | networkmanager | libnm-dev          | NetworkManager-libnm       | libnm-devel"
    "qt6-base        | lib:/usr/lib/libQt6Core.so.6 | qt6-base   | libqt6core6          | qt6-qtbase                 | libQt6Core6"
    "qt6-dbus        | lib:/usr/lib/libQt6DBus.so.6 | qt6-base   | libqt6dbus6          | qt6-qtbase                 | libQt6DBus6"
    "gcc             | bin:g++            | gcc                 | g++                      | gcc-c++                    | gcc-c++"
    "pkg-config      | bin:pkg-config     | pkgconf             | pkg-config               | pkgconf                    | pkg-config"
    "glib2           | lib:/usr/lib/libglib-2.0.so.0 | glib2     | libglib2.0-dev          | glib2-devel                | glib2-devel"
    "quickshell      | bin:qs             | quickshell          | quickshell               | quickshell                 | quickshell"
)

# ── 4. Check what's missing ───────────────────────────────────────────────────
is_installed() {
    local check="$1"
    local kind="${check%%:*}"
    local val="${check#*:}"
    case "$kind" in
        bin) command -v "$val" &>/dev/null ;;
        lib) test -f "$val" ;;
        pkg) "$PM" -Q "$val" &>/dev/null 2>&1 ;;
    esac
}

pm_pkg_for() {
    local entry="$1"
    # entry fields: label | check | pacman | apt | dnf | zypper
    IFS='|' read -ra fields <<< "$entry"
    local idx
    case "$PM" in
        pacman) idx=2 ;;
        apt)    idx=3 ;;
        dnf)    idx=4 ;;
        zypper) idx=5 ;;
    esac
    echo "${fields[$idx]}" | tr -d ' '
}

MISSING_PKGS=()       # packages to install
ALREADY_LABELS=()     # labels that were already present
MISSING_LABELS=()     # labels that were missing

for entry in "${DEPS[@]}"; do
    IFS='|' read -ra fields <<< "$entry"
    local_label="${fields[0]}" ; local_label="${local_label// /}"
    local_check="${fields[1]}" ; local_check="${local_check// /}"
    local_pkg="$(pm_pkg_for "$entry")"

    if is_installed "$local_check"; then
        ALREADY_LABELS+=("$local_label")
    else
        MISSING_LABELS+=("$local_label ($local_pkg)")
        MISSING_PKGS+=("$local_pkg")
    fi
done

# ── 5. Deduplicate package list ───────────────────────────────────────────────
declare -A seen
UNIQUE_PKGS=()
for p in "${MISSING_PKGS[@]}"; do
    [ -n "${seen[$p]}" ] && continue
    seen[$p]=1
    UNIQUE_PKGS+=("$p")
done

# ── 6. Ask and install ────────────────────────────────────────────────────────
if [ ${#UNIQUE_PKGS[@]} -eq 0 ]; then
    echo "[install] All dependencies already installed."
else
    echo ""
    echo "[install] Missing dependencies:"
    for lbl in "${MISSING_LABELS[@]}"; do
        echo "  - $lbl"
    done
    echo ""
    read -rp "[install] Install missing packages now? [Y/n] " answer
    answer="${answer:-Y}"
    if [[ "$answer" =~ ^[Yy] ]]; then
        case "$PM" in
            pacman) sudo pacman -S --needed --noconfirm "${UNIQUE_PKGS[@]}" ;;
            apt)    sudo apt-get install -y              "${UNIQUE_PKGS[@]}" ;;
            dnf)    sudo dnf install -y                  "${UNIQUE_PKGS[@]}" ;;
            zypper) sudo zypper install -y               "${UNIQUE_PKGS[@]}" ;;
        esac
        INSTALLED_NOW=("${UNIQUE_PKGS[@]}")
    else
        echo "[install] Skipped. Some features may not work."
        INSTALLED_NOW=()
    fi
fi

# ── 7. Save state ─────────────────────────────────────────────────────────────
# Save which packages we installed (so uninstall only removes those)
already_json="["
first=1
for lbl in "${ALREADY_LABELS[@]}"; do
    [ $first -eq 0 ] && already_json+=","
    already_json+="\"$lbl\""
    first=0
done
already_json+="]"

installed_json="["
first=1
for pkg in "${INSTALLED_NOW[@]:-}"; do
    [ -z "$pkg" ] && continue
    [ $first -eq 0 ] && installed_json+=","
    installed_json+="\"$pkg\""
    first=0
done
installed_json+="]"

cat > "$PKG_STATE" <<EOF
{
  "pm": "$PM",
  "already_installed": $already_json,
  "installed_by_aethera": $installed_json
}
EOF

echo "[install] State saved to $PKG_STATE"
echo "[install] Done."
