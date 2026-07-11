{ package }:

# What to do with a declared model list: pull anything missing, remove
# anything installed that's no longer declared. `ollama list`'s own
# table output is used directly instead of curling the HTTP API and
# parsing JSON -- one less moving part. The declared list itself is data
# (cfg.models, set in config/self-hosted.nix); this is the
# service-specific *behavior* for that data. Declared list arrives via
# $OLLAMA_MODELS_DECLARED (space-separated), set by ./ollama.nix.

''
  set -euo pipefail
  BIN="${package}/bin/ollama"

  if ! "$BIN" list >/dev/null 2>&1; then
    echo "[sync] ollama not reachable -- is self-hosted-ollama running?" >&2
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
