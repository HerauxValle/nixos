#!/usr/bin/env bash
# &desc: "gitctl push -- pushes declared repo(s) per their configured remotes/modes: squash snapshot (isolated tmp repo, force-push) or history (real commits, rebase+push)."

_push_squash_remote() { # $1=name $2=path $3=remote_name $4=url $5=exclude_paths_json
  local name="$1" path="$2" remote_name="$3" url="$4" excludes="$5" tmp
  tmp="$(gitctl_make_snapshot "$name" "$path" "$excludes")" || return 1
  if git -C "$tmp" push -q -f "$url" main; then
    log ok "'$name' -> '$remote_name': pushed (squash)"
  else
    log error "'$name' -> '$remote_name': push failed"
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
}

_push_history_remote() { # $1=name $2=path $3=remote_name $4=url $5=exclude_files_json
  local name="$1" path="$2" remote_name="$3" url="$4" exclude_files="$5" branch

  if [[ ! -d "$path/.git" ]]; then
    log error "'$name': history mode requires an existing git repo at $path"
    return 1
  fi

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    git -C "$path" update-index --assume-unchanged "$rel" 2> /dev/null || true
  done < <(jq -r '.[]' <<< "$exclude_files")

  git -C "$path" add -A
  if ! git -C "$path" diff --cached --quiet; then
    git -C "$path" -c "user.name=$GITCTL_COMMIT_NAME" -c "user.email=$GITCTL_COMMIT_EMAIL" \
      commit -q -m "update $(date '+%Y-%m-%d %H:%M')"
  fi

  if git -C "$path" remote get-url "$remote_name" > /dev/null 2>&1; then
    git -C "$path" remote set-url "$remote_name" "$url"
  else
    git -C "$path" remote add "$remote_name" "$url"
  fi

  branch="$(git -C "$path" branch --show-current)"
  git -C "$path" fetch -q "$remote_name" || true
  if ! git -C "$path" pull --rebase -q "$remote_name" "$branch" 2> /dev/null; then
    log warn "'$name' -> '$remote_name': rebase skipped (remote branch may not exist yet)"
  fi

  if git -C "$path" push -q "$remote_name" "$branch"; then
    log ok "'$name' -> '$remote_name': pushed (history)"
  else
    log error "'$name' -> '$remote_name': push failed"
    return 1
  fi
}

cmd_push() {
  local names=("$@") status=0 name entry path

  [[ ${#names[@]} -eq 0 ]] && mapfile -t names < <(gitctl_all_names)

  for name in "${names[@]}"; do
    if ! entry="$(gitctl_entry "$name")"; then
      log error "unknown repo: '$name'"
      status=1
      continue
    fi
    path="$(jq -r '.path' <<< "$entry")"
    if ! gitctl_require_path "$name" "$path"; then
      status=1
      continue
    fi
    while IFS=$'\t' read -r remote_name url mode; do
      [[ -z "$remote_name" ]] && continue
      if [[ "$mode" == "squash" ]]; then
        _push_squash_remote "$name" "$path" "$remote_name" "$url" "$(jq -c '.excludePaths' <<< "$entry")" || status=1
      else
        _push_history_remote "$name" "$path" "$remote_name" "$url" "$(jq -c '.excludeFiles' <<< "$entry")" || status=1
      fi
    done < <(jq -r '.remotes | to_entries[] | "\(.key)\t\(.value.url)\t\(.value.mode)"' <<< "$entry")
  done

  exit "$status"
}
