#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$DIR/binary"
mkdir -p "$BIN"

# Binaries are named mybar-* (not just e.g. "netmonitor") so they can be
# resolved unambiguously off $PATH regardless of how/where they were built —
# same convention whether this script ran directly (Arch/etc., binaries end
# up in $BIN) or inside the Nix derivation (Quickshell/MyBar/backend.nix,
# which runs this exact script during its buildPhase and installs the
# results to $out/bin).

# ── appscanner ────────────────────────────────────────────────────────────────
echo "[compile] Building appscanner..."
g++ -O2 -std=c++17 \
    -o "$BIN/mybar-appscanner" \
    "$DIR/source/appscanner/appscanner.cpp"
echo "[compile] Done — $BIN/mybar-appscanner"

# ── cpumonitor ────────────────────────────────────────────────────────────────
echo "[compile] Building cpumonitor..."
g++ -O2 -std=c++17 \
    -o "$BIN/mybar-cpumonitor" \
    "$DIR/source/cpumonitor/cpumonitor.cpp"
echo "[compile] Done — $BIN/mybar-cpumonitor"

# ── memmonitor ────────────────────────────────────────────────────────────────
echo "[compile] Building memmonitor..."
g++ -O2 -std=c++17 \
    -o "$BIN/mybar-memmonitor" \
    "$DIR/source/memmonitor/memmonitor.cpp"
echo "[compile] Done — $BIN/mybar-memmonitor"

# ── netmonitor (requires libnm + glib) ───────────────────────────────────────
echo "[compile] Building netmonitor..."
NM_CFLAGS=$(pkg-config --cflags libnm)
NM_LIBS=$(pkg-config --libs libnm)
g++ -O2 -std=c++17 \
    $NM_CFLAGS \
    -o "$BIN/mybar-netmonitor" \
    "$DIR/source/netmonitor/netmonitor.cpp" \
    $NM_LIBS
echo "[compile] Done — $BIN/mybar-netmonitor"

# ── notifserver (requires Qt6DBus + moc) ─────────────────────────────────────
echo "[compile] Building notifserver..."

# moc's location isn't standardized across distros/Nix (Arch: /usr/lib/qt6/moc,
# Nix: $qtbase/libexec/moc, some distros put it on PATH as moc6). Ask Qt itself
# via pkg-config first (Qt6Core.pc defines `libexecdir`), which is correct
# everywhere Qt ships one, before falling back to PATH/known locations.
find_moc() {
    for c in moc6 moc; do
        command -v "$c" >/dev/null 2>&1 && command -v "$c" && return
    done
    local libexec
    libexec=$(pkg-config --variable=libexecdir Qt6Core 2>/dev/null || true)
    if [ -n "$libexec" ] && [ -x "$libexec/moc" ]; then
        echo "$libexec/moc"
        return
    fi
    for p in /usr/lib/qt6/moc /usr/lib/qt6/libexec/moc /usr/lib64/qt6/libexec/moc; do
        [ -x "$p" ] && echo "$p" && return
    done
    return 1
}
MOC=$(find_moc) || { echo "[compile] ERROR: could not locate Qt6 moc (checked PATH, pkg-config, common paths)"; exit 1; }

QT_CFLAGS=$(pkg-config --cflags Qt6DBus Qt6Core)
QT_LIBS=$(pkg-config --libs Qt6DBus Qt6Core)

NOTIF_SRC="$DIR/source/notifserver"
NOTIF_MOC="$NOTIF_SRC/moc_notifserver.cpp"

"$MOC" $QT_CFLAGS "$NOTIF_SRC/notifserver.h" -o "$NOTIF_MOC"
g++ -O2 -std=c++17 \
    $QT_CFLAGS \
    -o "$BIN/mybar-notifserver" \
    "$NOTIF_SRC/notifserver.cpp" \
    "$NOTIF_MOC" \
    $QT_LIBS
rm -f "$NOTIF_MOC"
echo "[compile] Done — $BIN/mybar-notifserver"
