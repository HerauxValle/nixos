#!/usr/bin/env bash
# &desc: "mcli shared helpers -- unit/socket-path naming and the <name> argument check every subcommand needs."

# nix-minecraft's own naming: services.minecraft-servers.servers.<name>
# becomes systemd unit minecraft-server-<name>.service and (with the
# default tmux management system this repo uses -- see
# config/software/programs/minecraft/servers/creative/package.nix)
# console socket /run/minecraft/<name>.sock.
unit_name() { echo "minecraft-server-${1}.service"; }
sock_path() { echo "/run/minecraft/${1}.sock"; }

# dataDir is config.software.programs.minecraft.settings.nix's
# services.minecraft-servers.dataDir -- hardcoded here same as sock_path's
# /run/minecraft above, since both are this repo's own fixed choice, not
# something nix-minecraft lets you look up at runtime.
server_properties_path() { echo "/home/herauxvalle/Images/Minecraft/servers/${1}/server.properties"; }

require_name() {
    if [ -z "${1:-}" ]; then
        echo "usage: mcli ${cmd_usage:-<command>} <name>" >&2
        exit 1
    fi
}

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; CYAN='\033[36m'; MAGENTA='\033[35m'; RESET='\033[0m'

# Runs "$@" in the background with a spinner in front of $msg and a
# growing/cycling "." ".." "..." trail after it (" <frame> <msg><dots>",
# spinner+text+dots in $color while running) so start/stop/restart/fail
# don't just sit on a silent blinking cursor for however long systemctl
# takes (Type=forking units in particular -- the creative server's own
# ExecStartPost can run 80s+, see package.nix). `sudo -v` upfront so a
# password prompt (if the cached ticket already expired) happens cleanly
# before the spinner starts overwriting the line, not interleaved with
# it. Each redraw ends in \033[K (erase to end of line) since the dot
# trail's length changes every frame -- without it, a shorter redraw
# leaves stray characters from the previous, longer one behind.
run_with_spinner() {
    local color="$1" msg="$2"
    shift 2
    sudo -v || return $?

    "$@" &
    local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' dot_frames=("" "." ".." "...") i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r %b%s %s%s%b\033[K' "$color" "${frames:i%${#frames}:1}" "$msg" "${dot_frames[i / 3 % 4]}" "$RESET"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid"
    local status=$?
    tput cnorm 2>/dev/null || true

    if [ "$status" -eq 0 ]; then
        printf '\r %b✓ %s%b\033[K\n' "$GREEN" "$msg" "$RESET"
    else
        printf '\r %b✗ %s%b\033[K\n' "$RED" "$msg" "$RESET"
    fi
    return "$status"
}
