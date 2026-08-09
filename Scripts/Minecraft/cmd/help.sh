#!/usr/bin/env bash
cat <<'EOF'
usage: mcli <command> <name>

  log <name>
      Attaches to the server's live tmux console
      (tmux -S /run/minecraft/<name>.sock attach). Ctrl-b d to detach
      without stopping the server.

  start <name>
      sudo systemctl start minecraft-server-<name>.

  stop <name>
      sudo systemctl stop minecraft-server-<name>.

  restart <name>
      sudo systemctl restart minecraft-server-<name>.

  fail <name>
      Unsticks a unit stuck in `failed` state: clears it
      (systemctl reset-failed) and starts it again, then prints status.
      Only acts if the unit is actually failed.

  rcon <name> [command...]
      Sends console commands over RCON instead of attaching to the tmux
      console -- no args opens an interactive mcrcon shell, args are
      sent as a one-shot command. Reads the port/password straight out
      of the server's own rendered server.properties.

  help
      Show this message.

e.g. mcli log creative
     mcli restart creative
     mcli fail creative
     mcli rcon creative
     mcli rcon creative say hello
EOF
