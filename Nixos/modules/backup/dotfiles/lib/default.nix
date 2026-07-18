{
  config,
  lib,
  pkgs,
  ...
}:

# Dotfiles GitHub backup
#
# Runs entirely as a system.activationScripts entry -- no systemd service
# or timer sits around in the background. Fires on every activation of
# this generation, not only an explicit rebuild -- a plain reboot
# re-activates the current generation too. The tag is timestamp-based and
# only created when something actually changed, so a no-op activation
# costs nothing beyond a local diff check.
#
# All local shell state below is prefixed dotfilesBackup* deliberately:
# NixOS concatenates EVERY system.activationScripts.* entry from every
# module into one single shell script sharing one global variable/function
# scope, not per-module isolation -- an unprefixed name here can collide
# with some other module's activation script.
#
# Structure: this file is the ONLY place Nix values get spliced into bash
# text (the "preamble" below -- store paths, cfg scalars, and the
# redact/replace/exclude data files, exactly one place instead of scattered
# across every fragment). Everything in ./activation/ is a plain, static
# .sh file with zero ${...} interpolation, referencing only the vars/
# functions the preamble exports -- real files a linter/shellcheck can
# actually check, the same reasoning ./scripts/'s real .py files exist
# instead of embedded `python3 -c '...'` one-liners. See ./resolve.nix for
# the pure-Nix value resolution this preamble's data files are built from.
let
  cfg = config.vars.backup.dotfilesBackup;
  resolved = import ./resolve.nix { inherit config lib cfg; };
  inherit (resolved) redactValueResolutions resolvedRedactValues;
  inherit (resolved) replaceValueResolutions resolvedReplaceValues;
  inherit (resolved) excludeHash;

  # An entry with none of *, ?, [ is a plain literal path -- everywhere
  # below treats it exactly like the old --path/rm -rf did (an exact/
  # prefix match, no matching engine involved). An entry containing any
  # of those is a gitignore-style glob instead -- see
  # ./scripts/exclude.py's own top comment for the matching engine and
  # the one real difference from an actual .gitignore (fnmatch's `*`
  # already crosses `/`).
  isGlobPattern = f: builtins.match ".*[*?\\[].*" f != null;

  # git-filter-repo's own --paths-from-file format: one entry per line,
  # `literal:` (the default, matches exactly like the old --path/
  # --invert-paths did) or `glob:` (fnmatch-based, see isGlobPattern
  # above) -- auto-picked per entry so an existing plain excludeFiles
  # entry keeps its exact prior matching behavior with zero change, while
  # a new pattern entry gets real glob matching, both in one file/one
  # git-filter-repo invocation.
  excludePathsFileContent = lib.concatMapStringsSep "\n" (
    f: if isGlobPattern f then "glob:${f}" else "literal:${f}"
  ) cfg.excludeFiles;

  # git-filter-repo's own replacements-file format: one "old==>new" per
  # line, literal by default (no regex escaping needed). Feeds the history
  # scrub so OLD commits get the same redaction/replacement as the current
  # snapshot, not just going forward. Combines redactValues and
  # replaceValues into one file since git-filter-repo only takes one
  # --replace-text argument -- both are just "old==>new" literal pairs to
  # it, it doesn't distinguish why a pair exists. Note this pass, unlike
  # the exclude/redact/replace scripts, isn't scoped to each entry's
  # `file` -- git-filter-repo's --replace-text matches per blob content
  # across the WHOLE repo's history, not one path. Already true of
  # redactValues before replaceValues existed; accepted here for the same
  # reason (an exact match of a specific line elsewhere is unlikely, and
  # for replaceValues `find` is typically even more specific than
  # redactValues' bare value).
  replaceTextFileContent = lib.concatStringsSep "\n" (
    (map (
      r: "${r.value}==>${lib.concatStrings (lib.replicate (builtins.stringLength r.value) "*")}"
    ) resolvedRedactValues)
    ++ (map (r: "${r.find}==>${r.replaceWith}") resolvedReplaceValues)
  );

  # --paths-from-file/--invert-paths args for excludeFiles, and
  # --replace-text for redactValues/replaceValues -- both guarded on
  # non-empty (--invert-paths with an empty paths file would keep nothing
  # at all, not everything; --replace-text with an empty file is simply
  # pointless). Baked into dotfilesBackupFilterRepo's own definition below
  # rather than checked at runtime -- both are plain facts about the
  # current config, already known at eval time.
  excludePathFilterArg = lib.optionalString (
    cfg.excludeFiles != [ ]
  ) ''--paths-from-file "$dotfilesBackupExcludePathsFile" --invert-paths'';
  replaceTextArg = lib.optionalString (
    resolvedRedactValues != [ ] || resolvedReplaceValues != [ ]
  ) ''--replace-text "$dotfilesBackupReplaceTextFile"'';

  gitSshCommand = "${pkgs.openssh}/bin/ssh -i ${cfg.keyFile} -o UserKnownHostsFile=${cfg.knownHostsFile} -o StrictHostKeyChecking=yes -o ConnectTimeout=${toString cfg.connectTimeoutSeconds}";

  # JSON for redact.py/replace.py (the entries actually applied) and for
  # preflight_check.py (the full resolution, including a failed one --
  # `value` is the resolved find/redact text, null when `success` is
  # false since there's nothing to check against then).
  redactApplyJson = builtins.toJSON resolvedRedactValues;
  replaceApplyJson = builtins.toJSON resolvedReplaceValues;
  redactChecksJson = builtins.toJSON (
    map (r: {
      inherit (r) file key;
      success = r.result.success;
      value = if r.result.success then r.result.value else null;
    }) redactValueResolutions
  );
  replaceChecksJson = builtins.toJSON (
    map (r: {
      inherit (r) file key;
      success = r.result.success;
      value = if r.result.success then r.result.value else null;
    }) replaceValueResolutions
  );

  # The preamble -- every Nix-interpolated value this module's bash
  # actually needs, as plain `export VAR=value` lines and a handful of
  # small wrapper functions, so every fragment concatenated after it
  # (./activation/*.sh) can just reference $dotfilesBackupFoo or call
  # dotfilesBackupFoo() with zero further interpolation. mktemp'd data
  # files created unconditionally (never explicitly cleaned up, same as
  # this module's own pre-split $dotfilesBackupReplaceTextFile always
  # was) -- a few bytes in /tmp, no worse than before.
  preamble = ''
    dotfilesBackupGit="${pkgs.git}/bin/git"
    dotfilesBackupOpensshKeygen="${pkgs.openssh}/bin/ssh-keygen"
    dotfilesBackupCurl="${pkgs.curl}/bin/curl"
    dotfilesBackupJq="${pkgs.jq}/bin/jq"
    dotfilesBackupGawk="${pkgs.gawk}/bin/awk"
    dotfilesBackupRsync="${pkgs.rsync}/bin/rsync"
    dotfilesBackupGitFilterRepo="${pkgs.git-filter-repo}/bin/git-filter-repo"
    dotfilesBackupPython3="${pkgs.python3}/bin/python3"
    dotfilesBackupGrep="${pkgs.gnugrep}/bin/grep"

    # The whole directory as ONE store path, not four separate
    # ''${./scripts/x.py} literals -- each of those would copy in as its
    # own independent, unrelated store path, breaking
    # preflight_check.py's own `from exclude import find_matches` (a
    # real sibling-file import, which needs exclude.py to actually be
    # sitting right next to it at runtime, not off in a different
    # store path with a different hash).
    dotfilesBackupScriptsDir="${./scripts}"
    dotfilesBackupRedactScript="$dotfilesBackupScriptsDir/redact.py"
    dotfilesBackupReplaceScript="$dotfilesBackupScriptsDir/replace.py"
    dotfilesBackupExcludeScript="$dotfilesBackupScriptsDir/exclude.py"
    dotfilesBackupPreflightCheckScript="$dotfilesBackupScriptsDir/preflight_check.py"

    dotfilesBackupSecretsDir="${cfg.secretsDir}"
    dotfilesBackupKeyFile="${cfg.keyFile}"
    dotfilesBackupKnownHostsFile="${cfg.knownHostsFile}"
    dotfilesBackupKeyType="${cfg.keyType}"
    dotfilesBackupKeyComment="${cfg.keyComment}"
    dotfilesBackupDotfilesPath="${cfg.dotfilesPath}"
    dotfilesBackupRepoCache="${cfg.repoCache}"
    dotfilesBackupRemoteUrl="${cfg.remoteUrl}"
    dotfilesBackupBranch="${cfg.branch}"
    dotfilesBackupTagDateFormat="${cfg.tagDateFormat}"
    dotfilesBackupCommitUserName="${cfg.commitUserName}"
    dotfilesBackupCommitUserEmail="${cfg.commitUserEmail}"
    dotfilesBackupConnectTimeoutSeconds="${toString cfg.connectTimeoutSeconds}"
    dotfilesBackupGithubMetaApiUrl="${cfg.githubMetaApiUrl}"
    dotfilesBackupGithubSecretScanErrorCode="${cfg.githubSecretScanErrorCode}"
    dotfilesBackupHostKeyFailureMarker="${cfg.hostKeyFailureMarker}"
    dotfilesBackupNetworkFailureMarker="${cfg.networkFailureMarker}"
    dotfilesBackupExcludeHashFile="${cfg.excludeHashFile}"
    dotfilesBackupExcludeHash="${excludeHash}"
    dotfilesBackupColorRed="${cfg.colorRed}"
    dotfilesBackupColorYellow="${cfg.colorYellow}"
    dotfilesBackupColorGreen="${cfg.colorGreen}"
    dotfilesBackupColorReset="${cfg.colorReset}"
    dotfilesBackupBorderText="${cfg.border}"
    dotfilesBackupLogLevel="${cfg.logLevel}"
    dotfilesBackupSshCommand="${gitSshCommand}"
    dotfilesBackupUseRepoCache="${if cfg.useRepoCache then "1" else ""}"
    dotfilesBackupScrubHistoryOnExcludeChange="${if cfg.scrubHistoryOnExcludeChange then "1" else ""}"

    export dotfilesBackupColorRed
    export dotfilesBackupColorYellow
    export dotfilesBackupColorGreen
    export dotfilesBackupColorReset

    dotfilesBackupExcludePatternsFile="$(mktemp)"
    cat > "$dotfilesBackupExcludePatternsFile" <<'EXCLUDEPATTERNSEOF'
    ${lib.concatStringsSep "\n" cfg.excludeFiles}
    EXCLUDEPATTERNSEOF

    dotfilesBackupExcludePathsFile="$(mktemp)"
    cat > "$dotfilesBackupExcludePathsFile" <<'EXCLUDEPATHSEOF'
    ${excludePathsFileContent}
    EXCLUDEPATHSEOF

    dotfilesBackupReplaceTextFile="$(mktemp)"
    cat > "$dotfilesBackupReplaceTextFile" <<'REPLACETEXTEOF'
    ${replaceTextFileContent}
    REPLACETEXTEOF

    dotfilesBackupRedactApplyFile="$(mktemp)"
    cat > "$dotfilesBackupRedactApplyFile" <<'REDACTAPPLYEOF'
    ${redactApplyJson}
    REDACTAPPLYEOF

    dotfilesBackupReplaceApplyFile="$(mktemp)"
    cat > "$dotfilesBackupReplaceApplyFile" <<'REPLACEAPPLYEOF'
    ${replaceApplyJson}
    REPLACEAPPLYEOF

    dotfilesBackupRedactChecksFile="$(mktemp)"
    cat > "$dotfilesBackupRedactChecksFile" <<'REDACTCHECKSEOF'
    ${redactChecksJson}
    REDACTCHECKSEOF

    dotfilesBackupReplaceChecksFile="$(mktemp)"
    cat > "$dotfilesBackupReplaceChecksFile" <<'REPLACECHECKSEOF'
    ${replaceChecksJson}
    REPLACECHECKSEOF

    # %b (not %s) for $1/colorReset -- both are ANSI escapes stored as
    # literal backslash-escaped text in the variable (e.g. "\033[0;31m"),
    # same as cfg.colorRed always was; %b is what makes printf actually
    # interpret that escape into a real ESC byte instead of printing the
    # four literal characters "\033[".
    dotfilesBackupBorder() {
      printf '%b%s%b\n' "$1" "$dotfilesBackupBorderText" "$dotfilesBackupColorReset"
    }

    # Refreshes known_hosts from GitHub's /meta API -- trust comes from
    # that HTTPS request's own TLS/CA chain (the same one every other
    # HTTPS fetch on this system already relies on), not from SSH
    # trust-on-first-use. Used both for the initial bootstrap and the
    # reactive recovery in ./activation/push/.
    dotfilesBackupRefreshKnownHosts() {
      local dotfilesBackupTmpKnownHosts
      dotfilesBackupTmpKnownHosts="$(mktemp)"
      if "$dotfilesBackupCurl" -fsS --connect-timeout "$dotfilesBackupConnectTimeoutSeconds" "$dotfilesBackupGithubMetaApiUrl" 2>/dev/null \
           | "$dotfilesBackupJq" -r --arg t "$dotfilesBackupKeyType" '.ssh_keys[] | select(startswith($t + " ")) | "github.com " + .' \
           > "$dotfilesBackupTmpKnownHosts" 2>/dev/null \
         && [ -s "$dotfilesBackupTmpKnownHosts" ]; then
        mv "$dotfilesBackupTmpKnownHosts" "$dotfilesBackupKnownHostsFile"
        chmod 644 "$dotfilesBackupKnownHostsFile"
        chown root:root "$dotfilesBackupKnownHostsFile"
      else
        rm -f "$dotfilesBackupTmpKnownHosts"
      fi
    }

    # One push attempt, capturing real stderr (needed for the reactive
    # recovery checks in ./activation/push/ and for logLevel "normal"
    # diagnostic output) without losing the exit code -- `$(cmd 2>&1
    # 1>/dev/null)` at the call site swaps the streams so only stderr
    # lands in the captured variable while `$?` still reflects the
    # actual push. $1 left unquoted deliberately -- an empty string (no
    # force) must vanish as zero arguments, not one empty one.
    dotfilesBackupGitPush() {
      "$dotfilesBackupGit" -C "$dotfilesBackupRepoPath" -c safe.directory="$dotfilesBackupRepoPath" -c core.sshCommand="$dotfilesBackupSshCommand" push -q $1 "$dotfilesBackupRemoteUrl" "$dotfilesBackupBranch" 2>&1 1>/dev/null
    }

    # Full filter-repo invocation, combining the excludeFiles path filter
    # and the redactValues/replaceValues text replacement in one
    # history-rewriting pass. git-filter-repo shells out to bare `git`
    # internally (e.g. `git fast-export`) instead of a full derivation
    # path -- unlike every other git call here, which uses
    # $dotfilesBackupGit directly and so doesn't care what's on PATH.
    # Activation scripts don't have git on PATH by default, so this needs
    # it prepended explicitly or git-filter-repo fails immediately with
    # FileNotFoundError before touching anything.
    # GIT_CONFIG_COUNT/KEY_0/VALUE_0, not a `-c` flag: git-filter-repo
    # shells out to its own `git` subprocesses internally (e.g. `git
    # show-ref`), which never see a `-c` passed to the outer
    # git-filter-repo invocation itself. An env-var config override is
    # inherited by every nested process, so it reaches those internal
    # calls too -- without it, repoCache's directory ownership (see
    # ./activation/snapshot.sh's own rsync --no-owner --no-group comment
    # for why that isn't root) trips git's dubious-ownership check there
    # and this fails on every activation that reaches it.
    #
    # `rm -f .git/filter-repo/already_ran` first: repoCache is a
    # PERSISTENT clone re-filtered every time excludeFiles/redactValues
    # actually changes, not a one-shot fresh clone -- but git-filter-repo
    # leaves that marker after every run and, if it's more than a day old
    # on the next run, interactively prompts "Treat this run as a
    # continuation... (Y/N)?" on stdin. `--force` does not cover this
    # specific check (it's a separate, age-gated prompt from the "not a
    # fresh clone" one --force suppresses). Confirmed live: with no TTY
    # reachable from inside an activation script, that prompt just hangs
    # `nixos-rebuild switch` forever waiting for input that can never
    # come. Deleting the marker first makes every run look fresh, so the
    # prompt never fires -- we don't want continuation semantics here
    # anyway, just a deterministic re-filter with the current args each
    # time.
    dotfilesBackupFilterRepo() {
      local dotfilesBackupFilterRepoDir="$1"
      ( cd "$dotfilesBackupFilterRepoDir" \
        && rm -f .git/filter-repo/already_ran \
        && PATH="$(dirname "$dotfilesBackupGit"):$PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="$dotfilesBackupFilterRepoDir" \
           "$dotfilesBackupGitFilterRepo" --force ${excludePathFilterArg} ${replaceTextArg} )
    }

    # The three snapshot-editing passes, run against a synced COPY on
    # every activation (repoCache or the throwaway tmp dir in
    # ./activation/snapshot.sh, never dotfilesPath itself) -- exclude
    # first, then redact, then replace. One process for the whole list
    # each, not one per entry -- see ./scripts/'s own files for why.
    dotfilesBackupApplyExclude() {
      "$dotfilesBackupPython3" "$dotfilesBackupExcludeScript" "$1" "$dotfilesBackupExcludePatternsFile"
    }
    dotfilesBackupApplyRedact() {
      "$dotfilesBackupPython3" "$dotfilesBackupRedactScript" "$1" "$dotfilesBackupRedactApplyFile"
    }
    dotfilesBackupApplyReplace() {
      "$dotfilesBackupPython3" "$dotfilesBackupReplaceScript" "$1" "$dotfilesBackupReplaceApplyFile"
    }
  '';
in
{
  # Stale excludeFiles/redactValues/replaceValues entries are checked at
  # activation runtime (./activation/preflight.sh, via
  # scripts/preflight_check.py), not here -- see that script's own top
  # comment for why. That means these checks only run when enable = true,
  # unlike an eval-time version would; an acceptable tradeoff since a
  # disabled backup has nothing to protect in the meantime anyway.
  # lib.optionalString, not lib.mkIf: system.activationScripts.<name>.text is
  # `types.lines` with NO default (nixpkgs' activation-script.nix), and every
  # key ever assigned into system.activationScripts gets its .text read
  # unconditionally by that module's own aggregation logic, regardless of
  # any mkIf wrapping used here. `mkIf false` contributes no definition at
  # all, so with nothing else defining this option, that combination made
  # this whole system fail to evaluate the instant enable = false was ever
  # actually exercised -- confirmed live, since every user of this module
  # (this repo's own local config included) always had enable hardcoded
  # true until dotfilesBackup.enable became a real opt-in toggle.
  # optionalString always yields a real string (empty when disabled), which
  # is what a default-less `types.lines` option actually needs.
  system.activationScripts.dotfilesBackup.text = lib.optionalString cfg.enable ''
      ${lib.optionalString cfg.skipOnTest ''
        if [ "''${NIXOS_ACTION:-}" = "test" ]; then
          exit 0
        fi
      ''}
    {
      ${preamble}
      ${builtins.readFile ./activation/preflight.sh}
      ${builtins.readFile ./activation/snapshot.sh}
      ${builtins.readFile ./activation/push.sh}

      dotfilesBackup_preflight
      dotfilesBackup_snapshot
      dotfilesBackup_push
    } ${lib.optionalString (cfg.logLevel == "silent") "> /dev/null 2>&1"}
  '';
}
