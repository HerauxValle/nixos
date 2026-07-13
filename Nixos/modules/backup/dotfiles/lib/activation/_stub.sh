#!/usr/bin/env bash
# Editor/shellcheck only -- never read by Nix, never actually sourced.
# ../default.nix concatenates a generated preamble (every dotfilesBackup*
# var export and function definition below) and every fragment in this
# directory into one script; each fragment adds an `if false; then
# source ./_stub.sh; fi` block (dead code, never executes -- same idea
# as Python's `if TYPE_CHECKING:`) so shellcheck resolves these names
# against this file's declarations instead of flagging them as
# undefined, without any of this ever running for real.
#
# Every declaration below is, by definition, only ever "read" by some
# OTHER file that sources this one -- shellcheck has no way to see that
# when checking this file directly (as opposed to via a fragment's own
# `source=./_stub.sh` resolution), so a file-wide disable here is the
# correct fix, not a swept-under-the-rug one: there is no real unused
# variable to find in a file whose only job is being sourced by others.
# shellcheck disable=SC2034
dotfilesBackupGit=""
dotfilesBackupOpensshKeygen=""
dotfilesBackupCurl=""
dotfilesBackupJq=""
dotfilesBackupGawk=""
dotfilesBackupRsync=""
dotfilesBackupGitFilterRepo=""
dotfilesBackupPython3=""
dotfilesBackupGrep=""

dotfilesBackupScriptsDir=""
dotfilesBackupRedactScript=""
dotfilesBackupReplaceScript=""
dotfilesBackupExcludeScript=""
dotfilesBackupPreflightCheckScript=""

dotfilesBackupSecretsDir=""
dotfilesBackupKeyFile=""
dotfilesBackupKnownHostsFile=""
dotfilesBackupKeyType=""
dotfilesBackupKeyComment=""
dotfilesBackupDotfilesPath=""
dotfilesBackupRepoCache=""
dotfilesBackupRemoteUrl=""
dotfilesBackupBranch=""
dotfilesBackupTagDateFormat=""
dotfilesBackupCommitUserName=""
dotfilesBackupCommitUserEmail=""
dotfilesBackupConnectTimeoutSeconds=""
dotfilesBackupGithubMetaApiUrl=""
dotfilesBackupGithubSecretScanErrorCode=""
dotfilesBackupHostKeyFailureMarker=""
dotfilesBackupNetworkFailureMarker=""
dotfilesBackupExcludeHashFile=""
dotfilesBackupExcludeHash=""
dotfilesBackupColorRed=""
dotfilesBackupColorYellow=""
dotfilesBackupColorGreen=""
dotfilesBackupColorReset=""
dotfilesBackupBorderText=""
dotfilesBackupLogLevel=""
dotfilesBackupSshCommand=""
dotfilesBackupUseRepoCache=""
dotfilesBackupScrubHistoryOnExcludeChange=""

dotfilesBackupExcludePatternsFile=""
dotfilesBackupExcludePathsFile=""
dotfilesBackupReplaceTextFile=""
dotfilesBackupRedactApplyFile=""
dotfilesBackupReplaceApplyFile=""
dotfilesBackupRedactChecksFile=""
dotfilesBackupReplaceChecksFile=""

# Runtime state a later fragment reads that an earlier one sets --
# declared here too so shellcheck doesn't flag e.g. push.sh
# reading $dotfilesBackupChanged as unassigned when checked on its own.
dotfilesBackupStart=""
dotfilesBackupTag=""
dotfilesBackupChanged=""
dotfilesBackupRepoPath=""
dotfilesBackupPushForce=""
dotfilesBackupTmp=""
dotfilesBackupPushOutput=""
dotfilesBackupPushRc=""
dotfilesBackupNetworkFailure=""
dotfilesBackupHostKeyRefreshed=""
dotfilesBackupSecretPaths=""
dotfilesBackupElapsed=""

dotfilesBackupBorder() { :; }
dotfilesBackupRefreshKnownHosts() { :; }
dotfilesBackupGitPush() { :; }
dotfilesBackupFilterRepo() { :; }
dotfilesBackupApplyExclude() { :; }
dotfilesBackupApplyRedact() { :; }
dotfilesBackupApplyReplace() { :; }
