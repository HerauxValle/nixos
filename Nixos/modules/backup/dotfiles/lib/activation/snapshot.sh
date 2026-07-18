#!/usr/bin/env bash
# &desc: "Dotfiles backup snapshot activation script -- checks deploy key, auto-heals missing .git, creates/updates snapshot tag."
# shellcheck disable=SC1091
# shellcheck source=./_stub.sh
if false; then
  source "$(dirname "${BASH_SOURCE[0]}")/_stub.sh"
fi

# Concatenated by ../default.nix right after preflight.sh; called right
# after dotfilesBackup_preflight. The early `return 0` below replaces
# what used to be one `if [ -f "$dotfilesBackupKeyFile" ]` wrapping this
# and dotfilesBackup_push's own entire body -- same effective behavior
# (nothing past this point runs without a deploy key, dotfilesBackup_push
# never got called by anything meaningfully because dotfilesBackupChanged
# would never get set to "1" either), but expressed as a real early exit
# from a real function instead of an `if` left open for a sibling file to
# close, which isn't valid bash in an individual file at all.
dotfilesBackup_snapshot() {
  if [ ! -f "$dotfilesBackupKeyFile" ]; then
    return 0
  fi

  # Only auto-heal if we are NOT using the repo cache, and .git doesn't exist
  if [ "$dotfilesBackupUseRepoCache" != "1" ] && [ ! -d "$dotfilesBackupDotfilesPath/.git" ]; then
    if [ ! -f "$dotfilesBackupKeyFile" ]; then
      printf '%b[dotfiles-backup-error] ============================================%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
      printf '%bwarning: Local dotfiles directory is missing its .git repository AND%b\n' "$dotfilesBackupColorYellow" "$dotfilesBackupColorReset" >&2
      printf '%bno backup deploy key exists yet at %s.%b\n' "$dotfilesBackupColorYellow" "$dotfilesBackupKeyFile" "$dotfilesBackupColorReset" >&2
      printf 'Pushes will be completely skipped until preflight key generation finishes.\n' >&2
      printf '%b[dotfiles-backup-error] ============================================%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
    else
      printf '%b[dotfiles-backup-autoheal] ============================================%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
      printf '%bwarning: Local dotfiles directory is missing its .git repository tracking.%b\n' "$dotfilesBackupColorYellow" "$dotfilesBackupColorReset" >&2
      printf 'info: Self-healing and auto-initializing fresh repository at:\n' >&2
      printf '      %s\n' "$dotfilesBackupDotfilesPath" >&2
      printf '%b[dotfiles-backup-autoheal] ============================================%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2

      "$dotfilesBackupGit" -C "$dotfilesBackupDotfilesPath" init -q -b "$dotfilesBackupBranch"
      "$dotfilesBackupGit" -C "$dotfilesBackupDotfilesPath" -c safe.directory="$dotfilesBackupDotfilesPath" remote add origin "$dotfilesBackupRemoteUrl" 2>/dev/null || true
      "$dotfilesBackupGit" -C "$dotfilesBackupDotfilesPath" -c safe.directory="$dotfilesBackupDotfilesPath" add -A 2>/dev/null || true
      "$dotfilesBackupGit" -C "$dotfilesBackupDotfilesPath" -c safe.directory="$dotfilesBackupDotfilesPath" -c user.name="$dotfilesBackupCommitUserName" -c user.email="$dotfilesBackupCommitUserEmail" commit -q -m "init empty backup state" 2>/dev/null || true
    fi
  fi

  dotfilesBackupTag="$(date "$dotfilesBackupTagDateFormat")"
  dotfilesBackupChanged=1

  if [ "$dotfilesBackupUseRepoCache" = "1" ]; then
    if [ ! -d "$dotfilesBackupRepoCache/.git" ]; then
      "$dotfilesBackupGit" -c safe.directory="$dotfilesBackupRepoCache" init -q -b "$dotfilesBackupBranch" "$dotfilesBackupRepoCache"
    fi
    chmod 700 "$dotfilesBackupRepoCache"
    chown root:root "$dotfilesBackupRepoCache"

    # excludeFiles/redactValues/replaceValues only protect commits made
    # AFTER an entry is added or a redacted/replaced value changes --
    # anything already committed under the old state stays exposed in
    # every earlier commit, both here and on the already-pushed remote,
    # until explicitly rewritten. Runs once per actual change (hash
    # comparison below), not on every activation.
    if [ "$dotfilesBackupScrubHistoryOnExcludeChange" = "1" ]; then
      if [ -d "$dotfilesBackupRepoCache/.git" ] \
         && "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" rev-parse HEAD >/dev/null 2>&1 \
         && [ "$(cat "$dotfilesBackupExcludeHashFile" 2>/dev/null)" != "$dotfilesBackupExcludeHash" ]; then
        # dotfilesBackupFilterRepo is chained into the SAME condition as
        # the pushes below (not run unconditionally beforehand) -- if it
        # fails, the hash file must not be written and this must not be
        # reported as success. Previously this crashed silently
        # (git-filter-repo failing) while the script still printed
        # "successfully...rewrote history" and marked the hash done,
        # permanently hiding that nothing was actually scrubbed.
        if dotfilesBackupFilterRepo "$dotfilesBackupRepoCache" \
           && "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" -c core.sshCommand="$dotfilesBackupSshCommand" push -q -f "$dotfilesBackupRemoteUrl" --all \
           && "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" -c core.sshCommand="$dotfilesBackupSshCommand" push -q -f "$dotfilesBackupRemoteUrl" --tags; then
          printf '%s' "$dotfilesBackupExcludeHash" > "$dotfilesBackupExcludeHashFile"
          dotfilesBackupBorder "$dotfilesBackupColorYellow" >&2
          printf '%bnote: excludeFiles/redactValues changed -- rewrote and force-pushed full%b\n' "$dotfilesBackupColorYellow" "$dotfilesBackupColorReset" >&2
          printf '%bhistory to apply it retroactively, not just for future commits.%b\n' "$dotfilesBackupColorYellow" "$dotfilesBackupColorReset" >&2
          dotfilesBackupBorder "$dotfilesBackupColorYellow" >&2
        else
          dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
          printf '%bwarning: excludeFiles/redactValues changed, but rewriting/force-pushing%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
          printf '%bhistory failed -- will retry next activation. Old commits on the remote%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
          printf '%bmay still expose the changed value(s) until this succeeds.%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
          dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
        fi
      fi
    fi

    # --no-owner --no-group: plain `-a` preserves ownership on the
    # DESTINATION'S OWN top-level directory too, not just the files under
    # it -- since dotfilesPath is owned by the regular user, that
    # silently reassigns repoCache itself away from root (set by `git
    # init` above) on every activation, undermining the root-owned
    # invariant the rest of secretsDir relies on. Confirmed live: this is
    # what made dotfilesBackupFilterRepo's internal git calls fail with
    # "dubious ownership" on every run once the scrub path was ever
    # exercised. Git doesn't track uid/gid in commits anyway, so nothing
    # here needs -o/-g preserved.
    "$dotfilesBackupRsync" -a --no-owner --no-group --delete --exclude=.git "$dotfilesBackupDotfilesPath/" "$dotfilesBackupRepoCache/"
    dotfilesBackupApplyExclude "$dotfilesBackupRepoCache"
    dotfilesBackupApplyRedact "$dotfilesBackupRepoCache"
    dotfilesBackupApplyReplace "$dotfilesBackupRepoCache"
    "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" add -A
    if "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" diff --cached --quiet; then
      # Read by push.sh's own early-return guard, a sibling fragment
      # concatenated after this one.
      # shellcheck disable=SC2034
      dotfilesBackupChanged=0
    else
      "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" -c user.name="$dotfilesBackupCommitUserName" -c user.email="$dotfilesBackupCommitUserEmail" commit -q -m "$dotfilesBackupTag"
    fi
    dotfilesBackupRepoPath="$dotfilesBackupRepoCache"
    dotfilesBackupPushForce=""
  else
    if [ -d "$dotfilesBackupRepoCache" ]; then
      rm -rf "$dotfilesBackupRepoCache"
    fi
    dotfilesBackupTmp="$(mktemp -d)"
    trap 'rm -rf "$dotfilesBackupTmp"' EXIT
    cp -a "$dotfilesBackupDotfilesPath/." "$dotfilesBackupTmp/" 2>/dev/null || true
    rm -rf "$dotfilesBackupTmp/.git"
    dotfilesBackupApplyExclude "$dotfilesBackupTmp"
    dotfilesBackupApplyRedact "$dotfilesBackupTmp"
    dotfilesBackupApplyReplace "$dotfilesBackupTmp"
    "$dotfilesBackupGit" -c safe.directory="$dotfilesBackupTmp" init -q -b "$dotfilesBackupBranch" "$dotfilesBackupTmp"
    "$dotfilesBackupGit" -C "$dotfilesBackupTmp" -c safe.directory="$dotfilesBackupTmp" add -A
    "$dotfilesBackupGit" -C "$dotfilesBackupTmp" -c safe.directory="$dotfilesBackupTmp" -c user.name="$dotfilesBackupCommitUserName" -c user.email="$dotfilesBackupCommitUserEmail" commit -q -m "$dotfilesBackupTag" || true
    # Both read by push.sh, a sibling fragment concatenated after this one.
    # shellcheck disable=SC2034
    dotfilesBackupRepoPath="$dotfilesBackupTmp"
    # shellcheck disable=SC2034
    dotfilesBackupPushForce="-f"
  fi
}
