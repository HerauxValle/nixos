#!/usr/bin/env bash
# &desc: "Per-repo reconciler -- clone if missing, remotes/local git config always enforced. Never touches commit history, working tree, or the currently checked-out branch."
#
# Usage: sync-one.sh <name> <path> <entryJson>
#
# entryJson fields: url, initialBranch, remotes, userName, userEmail,
# signingKey, gpgSign, hooksPath, excludesFile, extraConfig -- see
# ../default.nix for what each one means.
#
# Expects REPOCTL_GIT, REPOCTL_JQ (absolute store paths) already exported
# by the caller -- activation scripts don't have git/jq on PATH by
# default, so every call below uses these instead of a bare `git`/`jq`.
#
# Safety model: every mutating git call here is either (a) pure metadata
# (remote URLs, `git config --local ...`) with zero data-loss risk, or
# (b) a checkout that git itself refuses if it would overwrite untracked
# files -- no `--force`/`--hard` is ever passed anywhere in this script.
# A real conflict surfaces as a normal failed step below, not something
# this script tries to pre-empt or paper over.
#
# No `-e` (unlike this repo's other lib scripts) -- deliberately: a failed
# checkout shouldn't skip local git config below it, and a failed config
# key shouldn't skip the rest. Every mutating step tracks its own outcome
# in $fail instead, so one failure is reported without aborting the other,
# independent reconciliation steps for this same repo.
set -uo pipefail

name="$1" path="$2" entry_json="$3"

_dot() {
  # $1 = color code (32 green / 31 red / 33 yellow), $2 = message
  printf "  [ \033[%sm•\033[0m ] %s\n" "$1" "$2"
}

fail=0

url="$("$REPOCTL_JQ" -r '.url' <<< "$entry_json")"
initial_branch="$("$REPOCTL_JQ" -r '.initialBranch // empty' <<< "$entry_json")"
user_name="$("$REPOCTL_JQ" -r '.userName // empty' <<< "$entry_json")"
user_email="$("$REPOCTL_JQ" -r '.userEmail // empty' <<< "$entry_json")"
signing_key="$("$REPOCTL_JQ" -r '.signingKey // empty' <<< "$entry_json")"
gpg_sign="$("$REPOCTL_JQ" -r 'if .gpgSign == null then empty else (.gpgSign | tostring) end' <<< "$entry_json")"
hooks_path="$("$REPOCTL_JQ" -r '.hooksPath // empty' <<< "$entry_json")"
excludes_file="$("$REPOCTL_JQ" -r '.excludesFile // empty' <<< "$entry_json")"

mkdir -p "$(dirname "$path")"

# ---------------------------------------------------------------------
# Existence: clone if missing/empty, `git init` (never destructive --
# only ever adds .git/) if the dir already has unrelated files in it.
# Either way, ends with $path being a real repo before we go any further.
# ---------------------------------------------------------------------

if [[ -d "$path/.git" ]]; then
  : # already a repo -- nothing to do here, config reconciliation below
elif [[ ! -e "$path" ]] || [[ -z "$(ls -A "$path" 2>/dev/null)" ]]; then
  clone_args=("$REPOCTL_GIT" clone --quiet)
  [[ -n "$initial_branch" ]] && clone_args+=(--branch "$initial_branch")
  clone_args+=("$url" "$path")
  if "${clone_args[@]}"; then
    _dot 32 "'$name': cloned"
  else
    _dot 31 "'$name': FAILED (clone)"
    exit 1
  fi
else
  # Non-empty directory, not yet a repo -- `git init` only ever adds
  # .git/, it never touches an existing file, so this is always safe.
  if ! "$REPOCTL_GIT" -C "$path" init --quiet; then
    _dot 31 "'$name': FAILED (git init)"
    exit 1
  fi
fi

# ---------------------------------------------------------------------
# Remotes: origin + declared extras. Pure metadata, always enforced.
# ---------------------------------------------------------------------

_set_remote() {
  local remote_name="$1" remote_url="$2"
  if "$REPOCTL_GIT" -C "$path" remote get-url "$remote_name" >/dev/null 2>&1; then
    "$REPOCTL_GIT" -C "$path" remote set-url "$remote_name" "$remote_url" || fail=1
  else
    "$REPOCTL_GIT" -C "$path" remote add "$remote_name" "$remote_url" || fail=1
  fi
}

_set_remote origin "$url"

while IFS=$'\t' read -r remote_name remote_url; do
  [[ -z "$remote_name" ]] && continue
  _set_remote "$remote_name" "$remote_url"
done < <("$REPOCTL_JQ" -r '.remotes | to_entries[] | "\(.key)\t\(.value)"' <<< "$entry_json")

# ---------------------------------------------------------------------
# Content: attempted whenever this repo has zero commits yet -- checked
# fresh every run (not just "was this repo just created this run"), so a
# repo left in that state by a previous failed attempt (e.g. init
# succeeded, checkout then hit a conflict) keeps retrying on every
# subsequent rebuild instead of silently being treated as "done" just
# because .git/ already exists. A repo that already has any commits --
# whether from a clone moments ago or one that's existed for months --
# never has checkout attempted again. No --force anywhere -- if checkout
# would clobber untracked files, git refuses and that's reported as a
# failure, not silently overridden.
# ---------------------------------------------------------------------

if ! "$REPOCTL_GIT" -C "$path" rev-parse --verify -q HEAD >/dev/null; then
  if "$REPOCTL_GIT" -C "$path" fetch --quiet origin; then
    branch="$initial_branch"
    if [[ -z "$branch" ]]; then
      "$REPOCTL_GIT" -C "$path" remote set-head origin -a >/dev/null 2>&1
      branch="$("$REPOCTL_GIT" -C "$path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
    fi
    if [[ -z "$branch" ]]; then
      _dot 31 "'$name': FAILED (couldn't determine the remote's default branch -- set initialBranch explicitly)"
      fail=1
    elif "$REPOCTL_GIT" -C "$path" checkout -B "$branch" "origin/$branch" --; then
      _dot 32 "'$name': checked out '$branch'"
    else
      _dot 31 "'$name': FAILED (checkout -- pre-existing files conflict with '$url')"
      fail=1
    fi
  else
    _dot 31 "'$name': FAILED (fetch)"
    fail=1
  fi
fi

# ---------------------------------------------------------------------
# Local git config -- pure metadata, always enforced, never touches
# history/working tree. --local scope only, never global.
# ---------------------------------------------------------------------

[[ -n "$user_name" ]] && { "$REPOCTL_GIT" -C "$path" config --local user.name "$user_name" || fail=1; }
[[ -n "$user_email" ]] && { "$REPOCTL_GIT" -C "$path" config --local user.email "$user_email" || fail=1; }
[[ -n "$signing_key" ]] && { "$REPOCTL_GIT" -C "$path" config --local user.signingKey "$signing_key" || fail=1; }
[[ -n "$gpg_sign" ]] && { "$REPOCTL_GIT" -C "$path" config --local commit.gpgSign "$gpg_sign" || fail=1; }
[[ -n "$hooks_path" ]] && { "$REPOCTL_GIT" -C "$path" config --local core.hooksPath "$hooks_path" || fail=1; }
[[ -n "$excludes_file" ]] && { "$REPOCTL_GIT" -C "$path" config --local core.excludesFile "$excludes_file" || fail=1; }

while IFS=$'\t' read -r cfg_key cfg_value; do
  [[ -z "$cfg_key" ]] && continue
  "$REPOCTL_GIT" -C "$path" config --local "$cfg_key" "$cfg_value" || fail=1
done < <("$REPOCTL_JQ" -r '.extraConfig | to_entries[] | "\(.key)\t\(.value)"' <<< "$entry_json")

if [[ "$fail" == "0" ]]; then
  _dot 32 "'$name': ok"
else
  _dot 31 "'$name': completed with errors"
fi

exit "$fail"
