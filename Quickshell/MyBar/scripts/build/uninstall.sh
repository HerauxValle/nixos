#!/usr/bin/env bash
# uninstall.sh — remove only packages that install.sh added (not pre-existing ones).
# Reads ~/.config/mybar/state/pkgs.json to know what was installed.

set -e
PKG_STATE="$HOME/.config/mybar/state/pkgs.json"

if [ ! -f "$PKG_STATE" ]; then
    echo "[uninstall] No install state found at $PKG_STATE — nothing to remove."
    exit 0
fi

# Parse JSON with basic grep/sed (no jq dependency)
PM=$(grep '"pm"' "$PKG_STATE" | sed 's/.*"pm"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
# Extract installed_by_aethera array values
PKGS_RAW=$(sed -n '/"installed_by_aethera"/,/\]/p' "$PKG_STATE" | grep '"' | sed 's/.*"\([^"]*\)".*/\1/' | grep -v 'installed_by_aethera')

mapfile -t PKGS <<< "$PKGS_RAW"

# Filter empty lines
CLEAN_PKGS=()
for p in "${PKGS[@]}"; do
    p="${p//[[:space:]]/}"
    [ -n "$p" ] && CLEAN_PKGS+=("$p")
done

if [ ${#CLEAN_PKGS[@]} -eq 0 ]; then
    echo "[uninstall] No packages were installed by Aethera — nothing to remove."
    exit 0
fi

echo "[uninstall] The following packages were installed by Aethera Shell:"
for p in "${CLEAN_PKGS[@]}"; do
    echo "  - $p"
done
echo ""

TO_REMOVE=()
for pkg in "${CLEAN_PKGS[@]}"; do
    read -rp "[uninstall] Remove '$pkg'? [y/N] " answer
    answer="${answer:-N}"
    if [[ "$answer" =~ ^[Yy] ]]; then
        TO_REMOVE+=("$pkg")
    fi
done

if [ ${#TO_REMOVE[@]} -eq 0 ]; then
    echo "[uninstall] Nothing removed."
    exit 0
fi

echo "[uninstall] Removing: ${TO_REMOVE[*]}"
case "$PM" in
    pacman) sudo pacman -Rns --noconfirm "${TO_REMOVE[@]}" ;;
    apt)    sudo apt-get remove -y       "${TO_REMOVE[@]}" ;;
    dnf)    sudo dnf remove -y           "${TO_REMOVE[@]}" ;;
    zypper) sudo zypper remove -y        "${TO_REMOVE[@]}" ;;
    *)      echo "[uninstall] Unknown package manager '$PM' — remove manually: ${TO_REMOVE[*]}" ;;
esac

# Update state file to remove the uninstalled packages
remaining_json="["
first=1
for pkg in "${CLEAN_PKGS[@]}"; do
    removed=0
    for r in "${TO_REMOVE[@]}"; do [ "$r" = "$pkg" ] && removed=1 && break; done
    [ $removed -eq 1 ] && continue
    [ $first -eq 0 ] && remaining_json+=","
    remaining_json+="\"$pkg\""
    first=0
done
remaining_json+="]"

# Rewrite installed_by_aethera in state file
tmp=$(mktemp)
awk -v new="$remaining_json" '
    /"installed_by_aethera"/ { found=1 }
    found && /\]/ { print "  \"installed_by_aethera\": " new; found=0; next }
    found { next }
    { print }
' "$PKG_STATE" > "$tmp" && mv "$tmp" "$PKG_STATE"

# Re-enable any notification daemons that were disabled by launch.sh,
# but only those that were already installed before Aethera.
for unit in swaync dunst mako xfce4-notifyd notify-osd; do
    if systemctl --user list-unit-files "${unit}.service" 2>/dev/null | grep -q "${unit}"; then
        systemctl --user enable "${unit}.service" 2>/dev/null || true
        systemctl --user start  "${unit}.service" 2>/dev/null || true
        echo "[uninstall] Re-enabled ${unit}.service"
    fi
done

echo "[uninstall] Done."
