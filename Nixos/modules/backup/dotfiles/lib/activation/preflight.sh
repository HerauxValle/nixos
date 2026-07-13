#!/usr/bin/env bash
# shellcheck disable=SC1091
# shellcheck source=./_stub.sh
if false; then
  source "$(dirname "${BASH_SOURCE[0]}")/_stub.sh"
fi

# First fragment concatenated after the preamble by ../default.nix, which
# calls this (and dotfilesBackup_snapshot, dotfilesBackup_push) once each
# at the very end, in order. A real function, not top-level statements --
# same reason dotfilesBackup_snapshot/dotfilesBackup_push are functions:
# it makes this file independently parseable/shellcheck-able (a plain
# `if` spanning multiple concatenated files can't be, since a lone `if`
# with no matching `fi` -- or vice versa -- isn't valid bash on its own).
# Runtime checks, not config.warnings/eval-time builtins.pathExists --
# `nixos-rebuild switch` (as pacnix calls it) runs WITHOUT --impure, so
# builtins.pathExists/readFile on a plain string path outside the flake
# cannot reliably see the real filesystem at eval time and reports false
# negatives for files that genuinely exist. A real check at activation
# time always has real filesystem access, no such trap. See
# ../scripts/preflight_check.py for the actual excludeFiles/redactValues/
# replaceValues stale-entry warnings this used to print inline here.
dotfilesBackup_preflight() {
  "$dotfilesBackupPython3" "$dotfilesBackupPreflightCheckScript" \
    "$dotfilesBackupDotfilesPath" "$dotfilesBackupExcludePatternsFile" \
    "$dotfilesBackupRedactChecksFile" "$dotfilesBackupReplaceChecksFile"

  # Read by push.sh's elapsed-time calc, a sibling fragment concatenated
  # after this one, not by anything in this file itself.
  # shellcheck disable=SC2034
  dotfilesBackupStart="$(date +%s.%N)"
  mkdir -p "$dotfilesBackupSecretsDir"
  chmod 700 "$dotfilesBackupSecretsDir"
  chown root:root "$dotfilesBackupSecretsDir"

  if [ ! -f "$dotfilesBackupKeyFile" ]; then
    "$dotfilesBackupOpensshKeygen" -q -t "$dotfilesBackupKeyType" -N "" -C "$dotfilesBackupKeyComment" -f "$dotfilesBackupKeyFile"
    chmod 600 "$dotfilesBackupKeyFile"
    chmod 644 "$dotfilesBackupKeyFile.pub"
    chown root:root "$dotfilesBackupKeyFile" "$dotfilesBackupKeyFile.pub"
    dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
    printf '%bwarning: no deploy key existed -- generated a new one at %s.%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupKeyFile" "$dotfilesBackupColorReset" >&2
    printf '%bAdd the public key below to the Dotfiles repo on GitHub (Settings -> Deploy%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
    printf '%bkeys -> Add deploy key, tick "Allow write access") -- nothing will push%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
    printf '%buntil you do:%b\n' "$dotfilesBackupColorRed" "$dotfilesBackupColorReset" >&2
    printf '%b%s%b\n' "$dotfilesBackupColorYellow" "$(cat "$dotfilesBackupKeyFile.pub")" "$dotfilesBackupColorReset" >&2
    printf '%bnote: this backup push is optional -- set vars.dotfilesBackup.enable = false in%b\n' "$dotfilesBackupColorGreen" "$dotfilesBackupColorReset" >&2
    printf '%bNixos/modules/backup/dotfiles/default.nix to turn it off, or just ignore this%b\n' "$dotfilesBackupColorGreen" "$dotfilesBackupColorReset" >&2
    printf '%bwarning if you do not care about it right now.%b\n' "$dotfilesBackupColorGreen" "$dotfilesBackupColorReset" >&2
    dotfilesBackupBorder "$dotfilesBackupColorRed" >&2
  fi

  if [ ! -f "$dotfilesBackupKnownHostsFile" ]; then
    dotfilesBackupRefreshKnownHosts
  fi
}
