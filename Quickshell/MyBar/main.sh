#!/usr/bin/env bash
# main.sh -- Aethera Shell entry point.
#
# Usage:
#   bash main.sh               → install (if not installed) then launch
#   bash main.sh --launch      → launch only
#   bash main.sh --compile     → compile C++ binaries
#   bash main.sh --install     → install deps + compile (marks installed)
#   bash main.sh --uninstall   → remove installed deps (marks uninstalled)
#
# Curl install (clones latest release then runs install+launch):
#   bash <(curl -fsSL https://raw.githubusercontent.com/HerauxValle/Aethera/main/main.sh)

set -e

# ── Detect if we were piped from curl (no $0 path on disk) ───────────────────
_curled=0
if [ ! -f "$0" ] || [ "$0" = "bash" ] || [ "$0" = "/bin/bash" ] || [ "$0" = "/usr/bin/bash" ]; then
    _curled=1
fi

# ── Resolve DIR (where main.sh lives) ────────────────────────────────────────
if [ $_curled -eq 1 ]; then
    # Clone latest release into ~/Projects/MyBar
    INSTALL_DIR="${AETHERA_DIR:-$HOME/Projects/MyBar}"
    REPO="HerauxValle/Aethera"
    echo "[aethera] Curled -- cloning latest release of $REPO into $INSTALL_DIR..."

    LATEST_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep '"tarball_url"' | head -1 | sed 's/.*"tarball_url": "\([^"]*\)".*/\1/')

    if [ -z "$LATEST_URL" ]; then
        echo "[aethera] ERROR: Could not fetch latest release URL."
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    TMP=$(mktemp -d)
    curl -fsSL "$LATEST_URL" | tar -xz -C "$TMP" --strip-components=1
    cp -a "$TMP/." "$INSTALL_DIR/"
    rm -rf "$TMP"
    echo "[aethera] Cloned to $INSTALL_DIR"
    DIR="$INSTALL_DIR"
else
    DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# ── State paths ───────────────────────────────────────────────────────────────
STATE_DIR="$HOME/.config/mybar/state"
INSTALL_STATE="$STATE_DIR/installed"
mkdir -p "$STATE_DIR"

_is_installed() {
    [ -f "$INSTALL_STATE" ] && grep -q "^installed=true" "$INSTALL_STATE"
}

_mark_installed()   { echo "installed=true"  > "$INSTALL_STATE"; }
_mark_uninstalled() { echo "installed=false" > "$INSTALL_STATE"; }

# ── Binary check ──────────────────────────────────────────────────────────────
# On Nix, the mybar-* binaries are already on $PATH (built declaratively by
# Quickshell/MyBar/backend.nix via environment.systemPackages) -- check that
# before falling back to scanning $DIR/binary, which is only ever populated
# by a manual (non-Nix) `--compile`/`--install` run.
_binaries_exist() {
    command -v mybar-appscanner >/dev/null 2>&1 && return 0
    local bin_dir="$DIR/binary"
    [ -d "$bin_dir" ] || return 1
    local count
    count=$(find "$bin_dir" -maxdepth 1 -type f -executable | wc -l)
    [ "$count" -gt 0 ]
}

# ── Subcommands ───────────────────────────────────────────────────────────────
_do_compile()   { bash "$DIR/scripts/build/compile.sh"; }
_do_launch()    { exec bash "$DIR/scripts/launch/launch.sh"; }
_do_uninstall() { bash "$DIR/scripts/build/uninstall.sh"; }

_do_install() {
    if _is_installed; then
        echo "[aethera] Already installed. Run --uninstall first."
        exit 1
    fi
    bash "$DIR/scripts/build/install.sh"
    _mark_installed
}

_do_default() {
    if ! _is_installed; then
        echo "[aethera] Not installed -- running install first..."
        bash "$DIR/scripts/build/install.sh"
        _mark_installed
    fi
    if ! _binaries_exist; then
        echo "[aethera] Binaries missing -- compiling..."
        _do_compile
    fi
    _do_launch
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
if [ $# -eq 0 ]; then
    _do_default
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        --launch)    _do_launch    ;;
        --compile)   _do_compile   ;;
        --install)   _do_install   ;;
        --uninstall)
            if ! _is_installed; then
                echo "[aethera] Not installed -- nothing to uninstall."
                exit 1
            fi
            _do_uninstall
            _mark_uninstalled
            ;;
        *) echo "Unknown flag: $arg"
           echo "Usage: $0 [--launch|--compile|--install|--uninstall]"
           exit 1 ;;
    esac
done
