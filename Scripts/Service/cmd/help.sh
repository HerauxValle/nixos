#!/usr/bin/env bash
cat <<'EOF'
usage: service <command> <name>[@<sub>]

Thin wrapper around systemctl for self-hosted-* units -- takes just the
part you actually think in ("openwebui", "comfyui@sync") and adds the
self-hosted- prefix + .service suffix. Forgiving about an already-typed
self-hosted- prefix. @<sub> addresses a service's own template
subservices (comfyui@sync, ollama@update:deps:apply, ...) exactly the
way systemctl itself does -- passed straight through untouched.

  start <name>[@<sub>]
      sudo systemctl start self-hosted-<name>[@<sub>].

  stop <name>[@<sub>]
      sudo systemctl stop self-hosted-<name>[@<sub>].

  restart <name>[@<sub>]
      sudo systemctl restart self-hosted-<name>[@<sub>].

  fail <name>[@<sub>]
      Unsticks a unit stuck in `failed` state: clears it
      (systemctl reset-failed) and starts it again, then prints status.
      Only acts if the unit is actually failed.

  help
      Show this message.

e.g. service start openwebui
     service restart comfyui@sync
     service fail immich
EOF
