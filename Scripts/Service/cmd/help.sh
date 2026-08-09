#!/usr/bin/env bash
cat <<'EOF'
usage: service <command> <name>[@<sub>] [--silent]

Thin wrapper around systemctl for self-hosted-* units -- takes just the
part you actually think in ("openwebui", "comfyui@sync") and adds the
self-hosted- prefix + .service suffix. Forgiving about an already-typed
self-hosted- prefix. @<sub> addresses a service's own template
subservices (comfyui@sync, ollama@update:deps:apply, ...) exactly the
way systemctl itself does -- passed straight through untouched.

  start <name>[@<sub>] [--silent]
      sudo systemctl start self-hosted-<name>[@<sub>].

  stop <name>[@<sub>] [--silent]
      sudo systemctl stop self-hosted-<name>[@<sub>].

  restart <name>[@<sub>] [--silent]
      sudo systemctl restart self-hosted-<name>[@<sub>].

  fail <name>[@<sub>] [--silent]
      Unsticks a unit stuck in `failed` state: clears it
      (systemctl reset-failed) and starts it again, then prints status.
      Only acts if the unit is actually failed.

  --silent (start/stop/restart/fail only)
      Fires the systemctl call fully detached in the background and
      returns immediately, instead of showing a spinner and waiting for
      it to finish.

  help
      Show this message.

e.g. service start openwebui
     service restart comfyui@sync
     service restart comfyui@sync --silent
     service fail immich
EOF
