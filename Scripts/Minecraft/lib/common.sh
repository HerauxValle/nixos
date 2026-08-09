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
