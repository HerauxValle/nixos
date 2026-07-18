# &desc: "State tracking library managing read, write, and exclusion diff computations against a local manifest database file."

#!/usr/bin/env bash
# Sourced by sync.sh, build.sh, remove.sh. The manifest is the only way
# we know what we installed last time -- home-manager's own generation
# diffing doesn't see into venv dirs, since they're mutated by pip after
# the fact, not declared as home.file symlinks. See docs/DECISIONS.md.

: "${VENVCTL_MANIFEST:?VENVCTL_MANIFEST not set}"

manifest_ensure() {
  mkdir -p "$(dirname "$VENVCTL_MANIFEST")"
  [[ -f "$VENVCTL_MANIFEST" ]] || echo '{"venvs":{}}' > "$VENVCTL_MANIFEST"
}

manifest_read() {
  manifest_ensure
  cat "$VENVCTL_MANIFEST"
}

# All manifest names currently on disk (may include venvs dropped from
# config -- that's the point, sync.sh diffs this against declared names).
manifest_names() {
  manifest_read | jq -r '.venvs | keys[]'
}

manifest_get_path() {
  manifest_read | jq -r --arg n "$1" '.venvs[$n].path // empty'
}

manifest_get_packages() {
  manifest_read | jq -c --arg n "$1" '.venvs[$n].packages // {}'
}

# $1 = name, $2 = resolvedPath, $3 = packages json (name -> version)
manifest_write_entry() {
  local name="$1" path="$2" packages="$3" tmp
  tmp="$(mktemp)"
  manifest_read | jq --arg n "$name" --arg p "$path" --argjson pk "$packages" \
    '.venvs[$n] = {path: $p, packages: $pk}' > "$tmp"
  mv "$tmp" "$VENVCTL_MANIFEST"
}

manifest_remove_entry() {
  local name="$1" tmp
  tmp="$(mktemp)"
  manifest_read | jq --arg n "$name" 'del(.venvs[$n])' > "$tmp"
  mv "$tmp" "$VENVCTL_MANIFEST"
}

# $1 = space-separated list of currently-declared venv names.
# Prints manifest names that are no longer declared -- these get removed.
manifest_names_not_in() {
  local declared="$1" name
  while IFS= read -r name; do
    [[ " $declared " == *" $name "* ]] || echo "$name"
  done < <(manifest_names)
}
