#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Match on "-p .*MyBar" (the actual qs/quickshell invocation), not bare
# "MyBar" — this script's OWN invocation ("bash .../MyBar/scripts/launch/
# launch.sh") also contains "MyBar", so a bare-substring pkill matches and
# kills itself before ever reaching `exec qs`. Requiring "-p " first only
# matches the real qs/quickshell process, never a wrapper script's own path.
pkill -f -- "-p .*MyBar" 2>/dev/null || true
sleep 0.3

# Stop any notification daemons that auto-restart via systemd so they don't
# race back and re-grab org.freedesktop.Notifications after notifserver kills them.
for unit in swaync dunst mako xfce4-notifyd notify-osd; do
    systemctl --user stop "${unit}.service" 2>/dev/null || true
    systemctl --user disable "${unit}.service" 2>/dev/null || true
done

set -a
THEME="${AETHERA_THEME:-mountain}"
THEME_FILE="$DIR/themes/${THEME}.env"
[ -f "$THEME_FILE" ] && source "$THEME_FILE"

USER_OVERRIDE="$HOME/.config/mybar/theme.env"
[ -f "$USER_OVERRIDE" ] && source "$USER_OVERRIDE"

for f in "$HOME/.config/mybar/custom/"*.env; do
    [ -f "$f" ] && source "$f"
done
set +a

hyprctl keyword layerrule "blur"   "namespace:quickshell:mybar" 2>/dev/null || true
hyprctl keyword layerrule "xray 1" "namespace:quickshell:mybar" 2>/dev/null || true

# QML resolves the mybar-* backend binaries by bare name off $PATH. On Nix
# they come from environment.systemPackages (Quickshell/MyBar/backend.nix);
# on a manual/non-Nix install $DIR/binary (populated by
# scripts/build/compile.sh) provides them instead — same binary names either
# way, so this is the only place that needs to know both can exist.
export PATH="$DIR/binary:$PATH"

exec qs -p "$DIR" "$@"
