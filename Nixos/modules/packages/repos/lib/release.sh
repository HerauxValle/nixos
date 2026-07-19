#!/usr/bin/env bash
# &desc: "gitctl release -- squash-push + tag + optional GitHub Release for a named repo; release rm deletes both."

_resolve_changelog() { # $1=raw arg -> body text on stdout
  local raw="$1" tmp
  [[ -z "$raw" ]] && return 0
  if [[ "$raw" == "changelog" ]]; then
    tmp="$(mktemp --suffix=.md)"
    printf '# Changelog\n\n' > "$tmp"
    "${EDITOR:-nano}" "$tmp"
    cat "$tmp"
    rm -f "$tmp"
    return 0
  fi
  if [[ -f "$raw" ]]; then
    cat "$raw"
    return 0
  fi
  printf '%s' "$raw"
}

_release_create() { # $1=name $2=tag $3=changelog_arg
  local name="$1" tag="$2" changelog_arg="${3:-}"
  local entry path remote_name url tmp github_repo token body payload http_code

  if ! entry="$(gitctl_entry "$name")"; then
    log error "unknown repo: '$name'"
    exit 1
  fi
  path="$(jq -r '.path' <<< "$entry")"
  gitctl_require_path "$name" "$path" || exit 1

  # First declared remote is the release target -- same one-primary-
  # remote-per-project convention gitpushall.py used.
  remote_name="$(jq -r '.remotes | keys[0] // empty' <<< "$entry")"
  if [[ -z "$remote_name" ]]; then
    log error "'$name': no remotes declared"
    exit 1
  fi
  url="$(jq -r --arg r "$remote_name" '.remotes[$r].url' <<< "$entry")"

  tmp="$(gitctl_make_snapshot "$name" "$path" "$(jq -c '.excludePaths' <<< "$entry")")" || exit 1
  git -C "$tmp" tag "$tag"
  if ! git -C "$tmp" push -q -f "$url" main; then
    log error "'$name': push failed"
    rm -rf "$tmp"
    exit 1
  fi
  if ! git -C "$tmp" push -q "$url" "$tag"; then
    log error "'$name': tag push failed"
    rm -rf "$tmp"
    exit 1
  fi
  rm -rf "$tmp"
  log ok "'$name': pushed + tagged '$tag'"

  github_repo="$(jq -r '.githubRepo // empty' <<< "$entry")"
  if [[ -z "$github_repo" ]]; then
    log warn "'$name': no githubRepo configured -- skipping GitHub Release"
    return 0
  fi
  token="$(gitctl_token)"
  if [[ -z "$token" ]]; then
    log warn "'$name': no token from 'secrets github add token' -- skipping GitHub Release"
    return 0
  fi

  body="$(_resolve_changelog "$changelog_arg")"
  payload="$(jq -n --arg tag "$tag" --arg body "${body:-Release $tag}" \
    '{tag_name:$tag, name:$tag, body:$body, draft:false, prerelease:false}')"
  http_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: token $token" -H "Content-Type: application/json" \
    -d "$payload" "https://api.github.com/repos/$github_repo/releases")"
  if [[ "$http_code" == 2* ]]; then
    log ok "'$name': GitHub Release created for '$tag'"
  else
    log error "'$name': GitHub Release creation failed (HTTP $http_code)"
  fi
}

_release_rm() { # $1=name $2=tag
  local name="$1" tag="$2"
  local entry remote_name url github_repo token release_id tmp

  if ! entry="$(gitctl_entry "$name")"; then
    log error "unknown repo: '$name'"
    exit 1
  fi
  remote_name="$(jq -r '.remotes | keys[0] // empty' <<< "$entry")"
  if [[ -z "$remote_name" ]]; then
    log error "'$name': no remotes declared"
    exit 1
  fi
  url="$(jq -r --arg r "$remote_name" '.remotes[$r].url' <<< "$entry")"

  github_repo="$(jq -r '.githubRepo // empty' <<< "$entry")"
  token="$(gitctl_token)"
  if [[ -n "$github_repo" && -n "$token" ]]; then
    release_id="$(curl -s -H "Authorization: token $token" \
      "https://api.github.com/repos/$github_repo/releases/tags/$tag" | jq -r '.id // empty')"
    if [[ -n "$release_id" ]]; then
      curl -s -X DELETE -H "Authorization: token $token" \
        "https://api.github.com/repos/$github_repo/releases/$release_id" > /dev/null
      log ok "'$name': GitHub Release deleted for '$tag'"
    else
      log warn "'$name': no GitHub Release found for '$tag'"
    fi
  fi

  tmp="$(mktemp -d)"
  git -C "$tmp" init -q -b main
  if git -C "$tmp" push "$url" --delete "$tag" 2> /dev/null; then
    log ok "'$name': remote tag deleted ('$tag')"
  else
    log warn "'$name': remote tag '$tag' not found (already deleted?)"
  fi
  rm -rf "$tmp"
}

cmd_release() {
  if [[ "${1:-}" == "rm" ]]; then
    shift
    if [[ $# -lt 2 ]]; then
      log error "usage: pacnix github release rm <name> <tag>"
      exit 1
    fi
    _release_rm "$1" "$2"
  else
    if [[ $# -lt 2 ]]; then
      log error "usage: pacnix github release <name> <tag> [changelog]"
      exit 1
    fi
    _release_create "$1" "$2" "${3:-}"
  fi
}
