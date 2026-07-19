#!/usr/bin/env bash
# &desc: "Shared gitctl helpers -- entry lookup, existence checks, and the squash-snapshot builder used by both push and release."
#
# Expects GITCTL_DATA, GITCTL_COMMIT_NAME, GITCTL_COMMIT_EMAIL,
# GITCTL_TOKEN_FILE already exported by the gitctl wrapper. git/jq/
# curl are on PATH via gitctl's own runtimeInputs -- no absolute-path
# indirection needed here (unlike a home-manager activation script,
# this is a real installed binary with its own PATH).

gitctl_entry() { # $1=name -> entry json on stdout, or empty + nonzero if unknown
  local name="$1" entry
  entry="$(jq -c --arg n "$name" '.repos[$n] // empty' <<< "$GITCTL_DATA")"
  [[ -z "$entry" ]] && return 1
  printf '%s' "$entry"
}

gitctl_all_names() {
  jq -r '.repos | keys[]' <<< "$GITCTL_DATA"
}

gitctl_require_path() { # $1=name $2=path
  if [[ ! -d "$2" ]]; then
    log error "'$1': path does not exist: $2"
    return 1
  fi
}

# Builds an isolated tmp repo from $2 (source dir), stripping $3 (jq
# array of paths relative to $2) and .git, commits everything with the
# declared identity via -c (never touches any persistent gitconfig).
# Echoes the tmp dir path on stdout; caller is responsible for `rm -rf`
# once done with it.
gitctl_make_snapshot() { # $1=name $2=src_dir $3=exclude_paths_json
  local name="$1" src="$2" excludes_json="$3" tmp
  tmp="$(mktemp -d)"
  cp -a "$src"/. "$tmp"/
  rm -rf "${tmp:?}/.git"

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    rm -rf "${tmp:?}/${rel}"
  done < <(jq -r '.[]' <<< "$excludes_json")

  git -C "$tmp" init -q -b main
  git -C "$tmp" add -A
  if ! git -C "$tmp" -c "user.name=$GITCTL_COMMIT_NAME" -c "user.email=$GITCTL_COMMIT_EMAIL" \
    commit -q -m "update $(date '+%Y-%m-%d %H:%M')"; then
    log error "'$name': nothing to snapshot (empty after excludes?)"
    rm -rf "$tmp"
    return 1
  fi
  printf '%s' "$tmp"
}

gitctl_token() {
  [[ -f "$GITCTL_TOKEN_FILE" ]] && cat "$GITCTL_TOKEN_FILE"
}
