# &desc: "Ollama model reconciliation script -- postStart polling, pulls missing from OLLAMA_MODELS_DECLARED, removes undeclared installed models."

{ package }:

# What to do with a declared model list: pull anything missing, remove
# anything installed that's no longer declared. `ollama list`'s own
# table output is used directly instead of curling the HTTP API and
# parsing JSON -- one less moving part. The declared list itself is data
# (cfg.models, set in config/self-hosted.nix); this is the
# service-specific *behavior* for that data. Declared list arrives via
# $OLLAMA_MODELS_DECLARED (space-separated), set by ./ollama.nix.
#
# Runs as postStart (ExecStartPost), not preStart -- pull/rm/list all go
# through ollama's own HTTP API, which isn't up yet during preStart.
# ExecStartPost fires right after fork/exec, not once the server is
# actually accepting connections, so this waits (poll, bounded) rather
# than assuming ready.

''
  set -euo pipefail
  BIN="${package}/bin/ollama"

  ready=0
  for _ in $(seq 1 30); do
    if "$BIN" list >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [ "$ready" -ne 1 ]; then
    echo "[sync] ollama did not become ready within 30s" >&2
    exit 1
  fi

  installed="$("$BIN" list | tail -n +2 | awk '{print $1}')"
  base_of() { echo "''${1%%:*}"; }

  count=0
  for model in $OLLAMA_MODELS_DECLARED; do
    full="$model"
    [[ "$full" == *:* ]] || full="''${full}:latest"
    if echo "$installed" | grep -qxF "$full"; then
      echo "[ok] $model"
    else
      echo "[pull] $model"
      "$BIN" pull "$model"
    fi
    count=$((count + 1))
  done
  echo "[sync] $count declared"

  removed=0
  while IFS= read -r inst; do
    [[ -z "$inst" ]] && continue
    inst_base="$(base_of "$inst")"
    found=0
    for model in $OLLAMA_MODELS_DECLARED; do
      [[ "$(base_of "$model")" == "$inst_base" ]] && { found=1; break; }
    done
    if [[ "$found" -eq 0 ]]; then
      echo "[remove] $inst (not declared)"
      "$BIN" rm "$inst"
      removed=$((removed + 1))
    fi
  done <<< "$installed"
  echo "[sync] $removed removed"
''
