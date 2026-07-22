#!/usr/bin/env bash

# 1. Kill pypr gracefully (SIGTERM), but kill quickshell forcefully if needed.
# Match on "-p .*MyBar" (the actual qs/quickshell invocation's arguments),
# not a bare "MyBar" substring: nixpkgs' Qt wrapping renames the real binary
# to .quickshell-wrapped (so `pkill qs`/`pkill quickshell` never hit it), but
# a bare "MyBar" pattern also matches the wrapper scripts' own invocation
# (e.g. "bash .../MyBar/scripts/launch/launch.sh" contains "MyBar" too),
# which self-kills them before they ever reach `exec qs`. Requiring "-p "
# first matches only the real process, on any distro/wrapper.
pkill pypr
pkill -f -- "-p .*MyBar" >/dev/null 2>&1

# Give processes a moment to release their sockets naturally
sleep 0.2

# 2. Clean remaining sockets and cache
rm -f "/run/user/$(id -u)/hypr"/*/.pyprland.sock
rm -rf ~/.cache/quickshell/qmlcache/

# Pause to let things settle before relaunching
sleep 0.3

# 3. Relaunch everything cleanly (guarded: pyprland/mpd aren't currently
# declared as packages anywhere in the Nix config, so skip quietly instead of
# spamming "command not found" if they're missing)
command -v pypr >/dev/null 2>&1 && pypr &
command -v mpc  >/dev/null 2>&1 && mpc update &

# Regenerate fastfetch theme -- run from the real Dotfiles checkout (not the
# ~/.config/scripts symlinked copy) so theme.py's relative path lands in the
# actual writable Fastfetch/ dir, not the read-only Nix store.
[ -f ~/Dotfiles/Scripts/Reload/theme.py ] && python3 ~/Dotfiles/Scripts/Reload/theme.py &

# Launch custom bar -- via the XDG config path (home-manager symlinks
# Dotfiles/Quickshell -> ~/.config/quickshell), not the Dotfiles repo path,
# so this keeps working no matter where the repo itself lives/moves.
bash ~/.config/quickshell/MyBar/main.sh --launch >/dev/null 2>&1 &