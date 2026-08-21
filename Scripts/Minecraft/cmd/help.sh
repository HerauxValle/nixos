#!/usr/bin/env bash
cat <<'EOF'
usage: mcli <command> <name> [--silent]

  log <name>
      Attaches to the server's live tmux console
      (tmux -S /run/minecraft/<name>.sock attach). Ctrl-b d to detach
      without stopping the server.

  start <name> [--silent]
      sudo systemctl start minecraft-server-<name>.

  stop <name> [--silent]
      sudo systemctl stop minecraft-server-<name>.

  restart <name> [--silent]
      sudo systemctl restart minecraft-server-<name>.

  fail <name> [--silent]
      Unsticks a unit stuck in `failed` state: clears it
      (systemctl reset-failed) and starts it again, then prints status.
      Only acts if the unit is actually failed.

  --silent (start/stop/restart/fail only)
      Fires the systemctl call fully detached in the background and
      returns immediately, instead of showing a spinner and waiting for
      it to finish.

  rcon <name> [command...]
      Sends console commands over RCON instead of attaching to the tmux
      console -- no args opens an interactive mcrcon shell, args are
      sent as a one-shot command. Reads the port/password straight out
      of the server's own rendered server.properties.

  help
      Show this message.

e.g. mcli log creative
     mcli restart creative
     mcli restart creative --silent
     mcli fail creative
     mcli rcon creative
     mcli rcon creative say hello
EOF
