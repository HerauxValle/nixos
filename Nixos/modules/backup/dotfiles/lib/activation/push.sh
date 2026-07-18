#!/usr/bin/env bash
# &desc: "Dotfiles backup push activation script -- runs only if snapshot changed, detects network failures early to skip doomed recovery."
# shellcheck disable=SC1091
# shellcheck source=./_stub.sh
if false; then
  source "$(dirname "${BASH_SOURCE[0]}")/_stub.sh"
fi

# Concatenated by ../default.nix right after snapshot.sh; called right
# after dotfilesBackup_snapshot. The early `return 0` below replaces what
# used to be an `if [ "$dotfilesBackupChanged" = "1" ]` wrapping this
# entire function body -- dotfilesBackupChanged is only ever set to "1"
# inside dotfilesBackup_snapshot, so this still only runs when that one
# did (whether because there was no deploy key at all, or because there
# genuinely was nothing new to push).
dotfilesBackup_push() {
  if [ "$dotfilesBackupChanged" != "1" ]; then
    return 0
  fi

  dotfilesBackupPushOutput="$(dotfilesBackupGitPush "$dotfilesBackupPushForce")"
  dotfilesBackupPushRc=$?

  # A dead connection (DSL down, no route at all) can't be fixed by any
  # of the recovery below -- host-key refresh, force retry, and GH013
  # rewrite are all network calls that would just fail the same way
  # again, slowly. Detect it once, right here, and skip straight past
  # all of that to the plain error below instead of wasting time
  # repeating doomed network calls.
  dotfilesBackupNetworkFailure=0
  if [ "$dotfilesBackupPushRc" -ne 0 ] && printf '%s' "$dotfilesBackupPushOutput" | "$dotfilesBackupGrep" -qE "$dotfilesBackupNetworkFailureMarker"; then
    dotfilesBackupNetworkFailure=1
  fi

  # Each recovery below fires only on its own specific, detected failure
  # signature -- zero cost when the push just works, which is the common
  # case. Bounded to exactly one retry each; a retry that also fails
  # falls through to the real error below, not another attempt.
  dotfilesBackupHostKeyRefreshed=0
  if [ "$dotfilesBackupNetworkFailure" != "1" ] && [ "$dotfilesBackupPushRc" -ne 0 ] && printf '%s' "$dotfilesBackupPushOutput" | "$dotfilesBackupGrep" -q "$dotfilesBackupHostKeyFailureMarker"; then
    dotfilesBackupRefreshKnownHosts
    dotfilesBackupHostKeyRefreshed=1
    dotfilesBackupPushOutput="$(dotfilesBackupGitPush "$dotfilesBackupPushForce")"
    dotfilesBackupPushRc=$?
  fi

  # Force-retry and GH013 (secret scan) recovery only ever apply in
  # repoCache mode -- the non-cache mode already force-pushes every time
  # (dotfilesBackupPushForce is always "-f" there, set in
  # dotfilesBackup_snapshot), so neither recovery has anything left to add.
  if [ "$dotfilesBackupUseRepoCache" = "1" ]; then
    if [ "$dotfilesBackupNetworkFailure" != "1" ] && [ "$dotfilesBackupPushRc" -ne 0 ]; then
      dotfilesBackupPushOutput="$(dotfilesBackupGitPush "-f")"
      dotfilesBackupPushRc=$?
    fi

    dotfilesBackupSecretPaths=""
    if [ "$dotfilesBackupNetworkFailure" != "1" ] && [ "$dotfilesBackupPushRc" -ne 0 ] && printf '%s' "$dotfilesBackupPushOutput" | "$dotfilesBackupGrep" -q "$dotfilesBackupGithubSecretScanErrorCode"; then
      dotfilesBackupSecretPaths="$(printf '%s' "$dotfilesBackupPushOutput" | "$dotfilesBackupGrep" -oE 'path: [^[:space:]]+' | sed 's/^path: //' | sort -u | tr '\n' ' ')"
      printf '%bnote: GitHub secret scan triggered -- rewriting local backup history to strip: %s%b\n' "$dotfilesBackupColorYellow" "$dotfilesBackupSecretPaths" "$dotfilesBackupColorReset" >&2
      dotfilesBackupFilterRepo "$dotfilesBackupRepoCache" || true
      "$dotfilesBackupRsync" -a --no-owner --no-group --delete --exclude=.git "$dotfilesBackupDotfilesPath/" "$dotfilesBackupRepoCache/"
      dotfilesBackupApplyExclude "$dotfilesBackupRepoCache"
      dotfilesBackupApplyRedact "$dotfilesBackupRepoCache"
      dotfilesBackupApplyReplace "$dotfilesBackupRepoCache"
      "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" add -A
      "$dotfilesBackupGit" -C "$dotfilesBackupRepoCache" -c safe.directory="$dotfilesBackupRepoCache" -c user.name="$dotfilesBackupCommitUserName" -c user.email="$dotfilesBackupCommitUserEmail" commit -q --allow-empty -m "$dotfilesBackupTag"
      dotfilesBackupPushOutput="$(dotfilesBackupGitPush "-f")"
      dotfilesBackupPushRc=$?
    fi
  fi

  dotfilesBackupElapsed="$("$dotfilesBackupGawk" -v s="$dotfilesBackupStart" -v e="$(date +%s.%N)" 'BEGIN{printf "%.2f", e-s}')"

  if [ "$dotfilesBackupPushRc" -eq 0 ]; then
    "$dotfilesBackupGit" -C "$dotfilesBackupRepoPath" -c safe.directory="$dotfilesBackupRepoPath" tag -f "$dotfilesBackupTag"
    "$dotfilesBackupGit" -C "$dotfilesBackupRepoPath" -c safe.directory="$dotfilesBackupRepoPath" -c core.sshCommand="$dotfilesBackupSshCommand" push -q -f "$dotfilesBackupRemoteUrl" "$dotfilesBackupTag" 2>/dev/null \
      || echo "warning: dotfiles-backup pushed $dotfilesBackupBranch but the tag push failed" >&2
    if [ "$dotfilesBackupLogLevel" = "normal" ]; then
      dotfilesBackupBorder "$dotfilesBackupColorGreen"
      printf '%bsuccessfully pushed %s to %s (took %ss)%b\n' "$dotfilesBackupColorGreen" "$dotfilesBackupTag" "$dotfilesBackupRemoteUrl" "$dotfilesBackupElapsed" "$dotfilesBackupColorReset"
      if [ "$dotfilesBackupHostKeyRefreshed" = "1" ]; then
        printf "%bnote: github.com's host key had changed -- refreshed known_hosts automatically.%b\n" "$dotfilesBackupColorYellow" "$dotfilesBackupColorReset"
      fi
      if [ -n "${dotfilesBackupSecretPaths:-}" ]; then
        printf '%bnote: a secret was found and stripped from history in: %s%b\n' "$dotfilesBackupColorYellow" "$dotfilesBackupSecretPaths" "$dotfilesBackupColorReset"
      fi
      dotfilesBackupBorder "$dotfilesBackupColorGreen"
    fi
  elif [ "$dotfilesBackupNetworkFailure" = "1" ]; then
    dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
    printf '%berror: could not reach %s (took %ss) -- internet/network problem, not%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupRemoteUrl" "$dotfilesBackupElapsed" "$dotfilesBackupColorReset" >&2
    printf '%bsomething this script can fix. Try again once your connection is back.%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
    dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
    exit 1
  else
    dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
    printf '%berror: failed to push %s to %s (took %ss).%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupBranch" "$dotfilesBackupRemoteUrl" "$dotfilesBackupElapsed" "$dotfilesBackupColorReset" >&2
    if [ "$dotfilesBackupLogLevel" = "normal" ]; then
      printf '%bgit said:%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
      printf '%b%s%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupPushOutput" "$dotfilesBackupColorReset" >&2
    fi
    printf '%bPublic key, in case it needs (re-)adding as a deploy key with write%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
    printf '%baccess (Settings -> Deploy keys):%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
    printf '%b%s%b\n' "$dotfilesBackupColorYellow" "$(cat "$dotfilesBackupKeyFile.pub")" "$dotfilesBackupColorReset" >&2
    printf '%bnote: this backup push is optional -- set vars.dotfilesBackup.enable = false in%b\n' "$dotfilesBackupColorGreen" "$dotfilesBackupColorReset" >&2
    printf '%bNixos/modules/backup/dotfiles/default.nix to turn it off, or just ignore this%b\n' "$dotfilesBackupColorGreen" "$dotfilesBackupColorReset" >&2
    printf '%berror if you do not care about it right now.%b\n' "$dotfilesBackupColorGreen" "$dotfilesBackupColorReset" >&2
    dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
    exit 1
  fi
}
