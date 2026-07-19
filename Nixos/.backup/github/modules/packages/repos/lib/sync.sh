#!/usr/bin/env bash
# &desc: "Repo sync orchestrator -- dispatches every declared repo to sync-one.sh."
# Entry point invoked directly by repos.nix's home.activation block.
# Expects REPOCTL_LIBROOT, REPOCTL_DATA, REPOCTL_GIT, REPOCTL_JQ already
# exported by the caller.
set -euo pipefail

status=0
while IFS= read -r name; do
  path="$("$REPOCTL_JQ" -r --arg n "$name" '.[$n].path' <<< "$REPOCTL_DATA")"
  entry_json="$("$REPOCTL_JQ" -c --arg n "$name" '.[$n]' <<< "$REPOCTL_DATA")"
  bash "$REPOCTL_LIBROOT/sync-one.sh" "$name" "$path" "$entry_json" || status=1
done < <("$REPOCTL_JQ" -r 'keys[]' <<< "$REPOCTL_DATA")

exit "$status"
