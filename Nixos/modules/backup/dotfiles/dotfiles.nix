{ config, pkgs, lib, ... }:

let
  cfg = config.vars.dotfilesBackup;

  # redactValues' `key` resolved to an actual value once, here -- every
  # call site below (per-activation redaction, history scrub, GH013
  # recovery) reuses this instead of re-resolving.
  resolvedRedactValues = map
    (r: {
      inherit (r) file;
      value = toString (lib.attrByPath (lib.splitString "." r.key) (throw "modules/backup/dotfiles: redactValues key '${r.key}' does not resolve against config") config);
    })
    cfg.redactValues;

  # Pure function of excludeFiles + redactValues' own content (values
  # included, not just which keys are listed -- rotating a redacted value,
  # e.g. changing the email itself, must also trigger a rescrub even
  # though the key/file pair didn't change). Sorted first so reordering
  # either list alone doesn't trigger a scrub for nothing.
  excludeHash = builtins.hashString "sha256" (lib.concatStringsSep "\n" (
    (lib.sort (a: b: a < b) cfg.excludeFiles)
    ++ (lib.sort (a: b: a < b) (map (r: "${r.file}\t${r.value}") resolvedRedactValues))
  ));

  # Replaces one exact literal value with same-length asterisks AND
  # comments out the whole line it's on, in a file already synced into the
  # snapshot -- runs on every activation, on the CURRENT copy (separate
  # from the one-time history scrub below, which only handles OLD
  # commits). The comment is what makes this safe regardless of what
  # Nix/type the original line held (a bare number, an enum, whatever) --
  # asterisks alone only stay valid if the original was already a quoted
  # string; a commented-out line can never break syntax, full stop. Python
  # for exact literal substitution, not sed -- avoids regex-escaping a
  # MAC/email that may contain characters sed's search side treats
  # specially.
  redactApplyScript = dir: lib.concatMapStringsSep "\n" (r: ''
    if [ -f "${dir}/${r.file}" ]; then
      ${pkgs.python3}/bin/python3 -c '
import sys
path, value = sys.argv[1], sys.argv[2]
masked = "*" * len(value)
with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
    lines = fh.readlines()
out = []
for line in lines:
    if value in line:
        line = line.replace(value, masked)
        stripped = line.lstrip()
        indent = line[:len(line) - len(stripped)]
        line = indent + "# " + stripped
    out.append(line)
with open(path, "w", encoding="utf-8", errors="surrogateescape") as fh:
    fh.writelines(out)
' "${dir}/${r.file}" ${lib.escapeShellArg r.value}
    fi
  '') resolvedRedactValues;

  # git-filter-repo's own replacements-file format: one "old==>new" per
  # line, literal by default (no regex escaping needed). Feeds the history
  # scrub below so OLD commits get the same redaction as the current
  # snapshot, not just going forward.
  replaceTextFileContent = lib.concatMapStringsSep "\n"
    (r: "${r.value}==>${lib.concatStrings (lib.replicate (builtins.stringLength r.value) "*")}")
    resolvedRedactValues;

  # --path/--invert-paths args for excludeFiles, shared by both
  # git-filter-repo call sites below. Guarded on non-empty: --invert-paths
  # with zero --path args would keep nothing at all, not everything.
  excludePathFilterArgs = lib.optionalString (cfg.excludeFiles != [ ])
    (lib.concatMapStringsSep " " (f: ''--path "${f}"'') cfg.excludeFiles + " --invert-paths");

  # Full filter-repo invocation, combining the excludeFiles path filter and
  # the redactValues text replacement in one history-rewriting pass.
  # git-filter-repo shells out to bare `git` internally (e.g. `git
  # fast-export`) instead of a full derivation path -- unlike every other
  # git call in this file, which uses ${pkgs.git}/bin/git directly and so
  # doesn't care what's on PATH. Activation scripts don't have git on PATH
  # by default, so this needs it prepended explicitly or git-filter-repo
  # fails immediately with FileNotFoundError before touching anything.
  # Single-line on purpose (no embedded newline) -- the GH013 recovery call
  # site appends " || true" right after it on the same script line, which
  # a trailing newline here would break onto its own line (a bash syntax
  # error: a line starting with "||" has nothing to its left).
  # GIT_CONFIG_COUNT/KEY_0/VALUE_0, not a `-c` flag: git-filter-repo shells
  # out to its own `git` subprocesses internally (e.g. `git show-ref`), which
  # never see a `-c` passed to the outer git-filter-repo invocation itself.
  # An env-var config override is inherited by every nested process, so it
  # reaches those internal calls too -- without it, repoCache's directory
  # ownership (see the rsync --no-owner --no-group comment below for why
  # that isn't root) trips git's dubious-ownership check there and this
  # fails on every activation that reaches it.
  filterRepoCmd = dir: ''( cd "${dir}" && PATH="${pkgs.git}/bin:$PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="${dir}" ${pkgs.git-filter-repo}/bin/git-filter-repo --force ${excludePathFilterArgs} ${lib.optionalString (resolvedRedactValues != [ ]) ''--replace-text "$dotfilesBackupReplaceTextFile"''} )'';

  # -----------------------------------------------------------------
  # Real logic -- constructs commands / runs scripts, not just plain
  # facts. Everything that's just a value (including the derived paths
  # secretsDir/keyComment/keyFile/knownHostsFile/repoCache) lives in
  # Nixos/modules/backup/dotfiles/default.nix instead.
  # -----------------------------------------------------------------

  gitSshCommand = "${pkgs.openssh}/bin/ssh -i ${cfg.keyFile} -o UserKnownHostsFile=${cfg.knownHostsFile} -o StrictHostKeyChecking=yes -o ConnectTimeout=${toString cfg.connectTimeoutSeconds}";

  # Refreshes known_hosts from GitHub's /meta API -- trust comes from that
  # HTTPS request's own TLS/CA chain (the same one every other HTTPS fetch
  # on this system already relies on), not from SSH trust-on-first-use.
  # Used both for the initial bootstrap and the reactive recovery below.
  refreshKnownHosts = ''
    dotfilesBackupTmpKnownHosts="$(mktemp)"
    if ${pkgs.curl}/bin/curl -fsS --connect-timeout ${toString cfg.connectTimeoutSeconds} ${cfg.githubMetaApiUrl} 2>/dev/null \
         | ${pkgs.jq}/bin/jq -r '.ssh_keys[] | select(startswith("${cfg.keyType} ")) | "github.com " + .' \
         > "$dotfilesBackupTmpKnownHosts" 2>/dev/null \
       && [ -s "$dotfilesBackupTmpKnownHosts" ]; then
      mv "$dotfilesBackupTmpKnownHosts" "${cfg.knownHostsFile}"
      chmod 644 "${cfg.knownHostsFile}"
      chown root:root "${cfg.knownHostsFile}"
    else
      rm -f "$dotfilesBackupTmpKnownHosts"
    fi
  '';

  # One push attempt, capturing real stderr (needed for the reactive
  # recovery checks below and for logLevel's "normal" diagnostic output)
  # without losing the exit code -- `$(cmd 2>&1 1>/dev/null)` swaps the
  # streams so only stderr lands in the variable while `$?` still reflects
  # the actual push.
  gitPush = force: ''
    ${pkgs.git}/bin/git -C "$dotfilesBackupRepoPath" -c safe.directory="$dotfilesBackupRepoPath" -c core.sshCommand="${gitSshCommand}" push -q ${force} "${cfg.remoteUrl}" "${cfg.branch}" 2>&1 1>/dev/null
  '';

in

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
{
  # Stale excludeFiles/redactValues entries are now checked at activation
  # runtime instead (top of the script below), not here -- see the comment
  # there for why. That means these checks only run when enable = true,
  # unlike the eval-time version this replaced; an acceptable tradeoff
  # since a disabled backup has nothing to protect in the meantime anyway.
  system.activationScripts.dotfilesBackup.text = lib.mkIf cfg.enable ''
    ${lib.optionalString cfg.skipOnTest ''
      if [ "''${NIXOS_ACTION:-}" = "test" ]; then
        exit 0
      fi
    ''}
  {
    dotfilesBackupBorder() {
      printf '%b${cfg.border}${cfg.colorReset}\n' "$1"
    }

    # Runtime checks, not config.warnings/eval-time builtins.pathExists --
    # `nixos-rebuild switch` (as pacnix calls it) runs WITHOUT --impure, so
    # builtins.pathExists/readFile on a plain string path outside the flake
    # cannot reliably see the real filesystem at eval time and reports
    # false negatives for files that genuinely exist. A real bash test at
    # activation time always has real filesystem access, no such trap.
    ${lib.concatMapStringsSep "\n    " (f: ''
      if [ ! -e "${cfg.dotfilesPath}/${f}" ]; then
        printf '${cfg.colorYellow}warning: modules/backup/dotfiles: excludeFiles entry '"'"'${f}'"'"' does not exist -- renamed, typo'"'"'d, or never created? It is not excluding anything right now.${cfg.colorReset}\n' >&2
      fi
    '') cfg.excludeFiles}
    ${lib.concatMapStringsSep "\n    " (r: ''
      if [ ! -f "${cfg.dotfilesPath}/${r.file}" ]; then
        printf '${cfg.colorYellow}warning: modules/backup/dotfiles: redactValues entry '"'"'${r.file}'"'"' does not exist -- renamed, typo'"'"'d, or never created? Nothing is being redacted there right now.${cfg.colorReset}\n' >&2
      elif ! ${pkgs.gnugrep}/bin/grep -qF -- ${lib.escapeShellArg r.value} "${cfg.dotfilesPath}/${r.file}"; then
        printf '${cfg.colorYellow}warning: modules/backup/dotfiles: redactValues key '"'"'${r.key}'"'"' does not currently appear in ${r.file} -- stale entry? It is not redacting anything there right now.${cfg.colorReset}\n' >&2
      fi
    '') (lib.zipListsWith (r: rv: { inherit (r) file key; inherit (rv) value; }) cfg.redactValues resolvedRedactValues)}

    dotfilesBackupStart="$(date +%s.%N)"
    mkdir -p "${cfg.secretsDir}"
    chmod 700 "${cfg.secretsDir}"
    chown root:root "${cfg.secretsDir}"

    if [ ! -f "${cfg.keyFile}" ]; then
      ${pkgs.openssh}/bin/ssh-keygen -q -t ${cfg.keyType} -N "" -C "${cfg.keyComment}" -f "${cfg.keyFile}"
      chmod 600 "${cfg.keyFile}"
      chmod 644 "${cfg.keyFile}.pub"
      chown root:root "${cfg.keyFile}" "${cfg.keyFile}.pub"
      dotfilesBackupBorder "${cfg.colorRed}" >&2
      printf '${cfg.colorRed}warning: no deploy key existed -- generated a new one at ${cfg.keyFile}.${cfg.colorReset}\n' >&2
      printf '${cfg.colorRed}Add the public key below to the Dotfiles repo on GitHub (Settings -> Deploy${cfg.colorReset}\n' >&2
      printf '${cfg.colorRed}keys -> Add deploy key, tick "Allow write access") -- nothing will push${cfg.colorReset}\n' >&2
      printf '${cfg.colorRed}until you do:${cfg.colorReset}\n' >&2
      printf '${cfg.colorYellow}%s${cfg.colorReset}\n' "$(cat "${cfg.keyFile}.pub")" >&2
      printf '${cfg.colorGreen}note: this backup push is optional -- set vars.dotfilesBackup.enable = false in${cfg.colorReset}\n' >&2
      printf '${cfg.colorGreen}Nixos/modules/backup/dotfiles/default.nix to turn it off, or just ignore this${cfg.colorReset}\n' >&2
      printf '${cfg.colorGreen}warning if you do not care about it right now.${cfg.colorReset}\n' >&2
      dotfilesBackupBorder "${cfg.colorRed}" >&2
    fi

    if [ ! -f "${cfg.knownHostsFile}" ]; then
      ${refreshKnownHosts}
    fi

    if [ -f "${cfg.keyFile}" ]; then
      dotfilesBackupTag="$(date "${cfg.tagDateFormat}")"
      dotfilesBackupChanged=1

      ${lib.optionalString (resolvedRedactValues != [ ]) ''
        dotfilesBackupReplaceTextFile="$(mktemp)"
        cat > "$dotfilesBackupReplaceTextFile" <<'REPLACEEOF'
${replaceTextFileContent}
REPLACEEOF
      ''}

      ${if cfg.useRepoCache then ''
        if [ ! -d "${cfg.repoCache}/.git" ]; then
          ${pkgs.git}/bin/git -c safe.directory="${cfg.repoCache}" init -q -b "${cfg.branch}" "${cfg.repoCache}"
        fi
        chmod 700 "${cfg.repoCache}"
        chown root:root "${cfg.repoCache}"

        # excludeFiles/redactValues only protect commits made AFTER an
        # entry is added or a redacted value changes -- anything already
        # committed under the old state stays exposed in every earlier
        # commit, both here and on the already-pushed remote, until
        # explicitly rewritten. Runs once per actual change (hash
        # comparison below), not on every activation.
        ${lib.optionalString cfg.scrubHistoryOnExcludeChange ''
          if [ -d "${cfg.repoCache}/.git" ] \
             && ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" rev-parse HEAD >/dev/null 2>&1 \
             && [ "$(cat "${cfg.excludeHashFile}" 2>/dev/null)" != "${excludeHash}" ]; then
            # filterRepoCmd is chained into the SAME condition as the
            # pushes below (not run unconditionally beforehand) -- if it
            # fails, the hash file must not be written and this must not
            # be reported as success. Previously this crashed silently
            # (git-filter-repo failing) while the script still printed
            # "successfully...rewrote history" and marked the hash done,
            # permanently hiding that nothing was actually scrubbed.
            if ${filterRepoCmd cfg.repoCache} \
               && ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" -c core.sshCommand="${gitSshCommand}" push -q -f "${cfg.remoteUrl}" --all \
               && ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" -c core.sshCommand="${gitSshCommand}" push -q -f "${cfg.remoteUrl}" --tags; then
              printf '%s' "${excludeHash}" > "${cfg.excludeHashFile}"
              dotfilesBackupBorder "${cfg.colorYellow}" >&2
              printf '${cfg.colorYellow}note: excludeFiles/redactValues changed -- rewrote and force-pushed full${cfg.colorReset}\n' >&2
              printf '${cfg.colorYellow}history to apply it retroactively, not just for future commits.${cfg.colorReset}\n' >&2
              dotfilesBackupBorder "${cfg.colorYellow}" >&2
            else
              dotfilesBackupBorder "${cfg.colorRed}" >&2
              printf '${cfg.colorRed}warning: excludeFiles/redactValues changed, but rewriting/force-pushing${cfg.colorReset}\n' >&2
              printf '${cfg.colorRed}history failed -- will retry next activation. Old commits on the remote${cfg.colorReset}\n' >&2
              printf '${cfg.colorRed}may still expose the changed value(s) until this succeeds.${cfg.colorReset}\n' >&2
              dotfilesBackupBorder "${cfg.colorRed}" >&2
            fi
          fi
        ''}

        # --no-owner --no-group: plain `-a` preserves ownership on the
        # DESTINATION'S OWN top-level directory too, not just the files
        # under it -- since dotfilesPath is owned by the regular user, that
        # silently reassigns repoCache itself away from root (set by `git
        # init` above) on every activation, undermining the root-owned
        # invariant the rest of secretsDir relies on. Confirmed live: this
        # is what made git-filter-repo's internal git calls (filterRepoCmd
        # above) fail with "dubious ownership" on every run once the scrub
        # path was ever exercised. Git doesn't track uid/gid in commits
        # anyway, so nothing here needs -o/-g preserved.
        ${pkgs.rsync}/bin/rsync -a --no-owner --no-group --delete --exclude=.git "${cfg.dotfilesPath}/" "${cfg.repoCache}/"
        ${lib.concatMapStringsSep "\n        " (f: ''rm -rf "${cfg.repoCache}/${f}"'') cfg.excludeFiles}
        ${redactApplyScript cfg.repoCache}
        ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" add -A
        if ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" diff --cached --quiet; then
          dotfilesBackupChanged=0
        else
          ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" -c user.name="${cfg.commitUserName}" -c user.email="${cfg.commitUserEmail}" commit -q -m "$dotfilesBackupTag"
        fi
        dotfilesBackupRepoPath="${cfg.repoCache}"
        dotfilesBackupPushForce=""
      '' else ''
        if [ -d "${cfg.repoCache}" ]; then
          rm -rf "${cfg.repoCache}"
        fi
        dotfilesBackupTmp="$(mktemp -d)"
        trap 'rm -rf "$dotfilesBackupTmp"' EXIT
        cp -a "${cfg.dotfilesPath}/." "$dotfilesBackupTmp/" 2>/dev/null || true
        rm -rf "$dotfilesBackupTmp/.git"
        ${lib.concatMapStringsSep "\n        " (f: ''rm -rf "$dotfilesBackupTmp/${f}"'') cfg.excludeFiles}
        ${redactApplyScript "$dotfilesBackupTmp"}
        ${pkgs.git}/bin/git -c safe.directory="$dotfilesBackupTmp" init -q -b "${cfg.branch}" "$dotfilesBackupTmp"
        ${pkgs.git}/bin/git -C "$dotfilesBackupTmp" -c safe.directory="$dotfilesBackupTmp" add -A
        ${pkgs.git}/bin/git -C "$dotfilesBackupTmp" -c safe.directory="$dotfilesBackupTmp" -c user.name="${cfg.commitUserName}" -c user.email="${cfg.commitUserEmail}" commit -q -m "$dotfilesBackupTag" || true
        dotfilesBackupRepoPath="$dotfilesBackupTmp"
        dotfilesBackupPushForce="-f"
      ''}

      if [ "$dotfilesBackupChanged" = "1" ]; then
        dotfilesBackupPushOutput="$(${gitPush "$dotfilesBackupPushForce"})"
        dotfilesBackupPushRc=$?

        # A dead connection (DSL down, no route at all) can't be fixed by
        # any of the recovery below -- host-key refresh, force retry, and
        # GH013 rewrite are all network calls that would just fail the
        # same way again, slowly. Detect it once, right here, and skip
        # straight past all of that to the plain error below instead of
        # wasting time repeating doomed network calls.
        dotfilesBackupNetworkFailure=0
        if [ $dotfilesBackupPushRc -ne 0 ] && printf '%s' "$dotfilesBackupPushOutput" | grep -qE "${cfg.networkFailureMarker}"; then
          dotfilesBackupNetworkFailure=1
        fi

        # Each recovery below fires only on its own specific, detected
        # failure signature -- zero cost when the push just works, which
        # is the common case. Bounded to exactly one retry each; a retry
        # that also fails falls through to the real error below, not
        # another attempt.
        dotfilesBackupHostKeyRefreshed=0
        if [ "$dotfilesBackupNetworkFailure" != "1" ] && [ $dotfilesBackupPushRc -ne 0 ] && printf '%s' "$dotfilesBackupPushOutput" | grep -q "${cfg.hostKeyFailureMarker}"; then
          ${refreshKnownHosts}
          dotfilesBackupHostKeyRefreshed=1
          dotfilesBackupPushOutput="$(${gitPush "$dotfilesBackupPushForce"})"
          dotfilesBackupPushRc=$?
        fi

        ${lib.optionalString cfg.useRepoCache ''
          if [ "$dotfilesBackupNetworkFailure" != "1" ] && [ $dotfilesBackupPushRc -ne 0 ]; then
            dotfilesBackupPushOutput="$(${gitPush "-f"})"
            dotfilesBackupPushRc=$?
          fi

          dotfilesBackupSecretPaths=""
          if [ "$dotfilesBackupNetworkFailure" != "1" ] && [ $dotfilesBackupPushRc -ne 0 ] && printf '%s' "$dotfilesBackupPushOutput" | grep -q "${cfg.githubSecretScanErrorCode}"; then
            dotfilesBackupSecretPaths="$(printf '%s' "$dotfilesBackupPushOutput" | grep -oE 'path: [^[:space:]]+' | sed 's/^path: //' | sort -u | tr '\n' ' ')"
            printf '${cfg.colorYellow}note: GitHub secret scan triggered -- rewriting local backup history to strip: %s${cfg.colorReset}\n' "$dotfilesBackupSecretPaths" >&2
            ${filterRepoCmd cfg.repoCache} || true
            ${pkgs.rsync}/bin/rsync -a --no-owner --no-group --delete --exclude=.git "${cfg.dotfilesPath}/" "${cfg.repoCache}/"
            ${lib.concatMapStringsSep "\n            " (f: ''rm -rf "${cfg.repoCache}/${f}"'') cfg.excludeFiles}
            ${redactApplyScript cfg.repoCache}
            ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" add -A
            ${pkgs.git}/bin/git -C "${cfg.repoCache}" -c safe.directory="${cfg.repoCache}" -c user.name="${cfg.commitUserName}" -c user.email="${cfg.commitUserEmail}" commit -q --allow-empty -m "$dotfilesBackupTag"
            dotfilesBackupPushOutput="$(${gitPush "-f"})"
            dotfilesBackupPushRc=$?
          fi
        ''}

        dotfilesBackupElapsed="$(${pkgs.gawk}/bin/awk -v s="$dotfilesBackupStart" -v e="$(date +%s.%N)" 'BEGIN{printf "%.2f", e-s}')"

        if [ $dotfilesBackupPushRc -eq 0 ]; then
          ${pkgs.git}/bin/git -C "$dotfilesBackupRepoPath" -c safe.directory="$dotfilesBackupRepoPath" tag -f "$dotfilesBackupTag"
          ${pkgs.git}/bin/git -C "$dotfilesBackupRepoPath" -c safe.directory="$dotfilesBackupRepoPath" -c core.sshCommand="${gitSshCommand}" push -q -f "${cfg.remoteUrl}" "$dotfilesBackupTag" 2>/dev/null || echo "warning: dotfiles-backup pushed ${cfg.branch} but the tag push failed" >&2
          ${lib.optionalString (cfg.logLevel == "normal") ''
            dotfilesBackupBorder "${cfg.colorGreen}"
            printf '${cfg.colorGreen}successfully pushed %s to %s (took %ss)${cfg.colorReset}\n' "$dotfilesBackupTag" "${cfg.remoteUrl}" "$dotfilesBackupElapsed"
            if [ "$dotfilesBackupHostKeyRefreshed" = "1" ]; then
              printf '${cfg.colorYellow}note: github.com'"'"'s host key had changed -- refreshed known_hosts automatically.${cfg.colorReset}\n'
            fi
            if [ -n "''${dotfilesBackupSecretPaths:-}" ]; then
              printf '${cfg.colorYellow}note: a secret was found and stripped from history in: %s${cfg.colorReset}\n' "$dotfilesBackupSecretPaths"
            fi
            dotfilesBackupBorder "${cfg.colorGreen}"
          ''}
        elif [ "$dotfilesBackupNetworkFailure" = "1" ]; then
          dotfilesBackupBorder "${cfg.colorRed}" >&2
          printf '${cfg.colorRed}error: could not reach %s (took %ss) -- internet/network problem, not${cfg.colorReset}\n' "${cfg.remoteUrl}" "$dotfilesBackupElapsed" >&2
          printf '${cfg.colorRed}something this script can fix. Try again once your connection is back.${cfg.colorReset}\n' >&2
          dotfilesBackupBorder "${cfg.colorRed}" >&2
          exit 1
        else
          dotfilesBackupBorder "${cfg.colorRed}" >&2
          printf '${cfg.colorRed}error: failed to push %s to %s (took %ss).${cfg.colorReset}\n' "${cfg.branch}" "${cfg.remoteUrl}" "$dotfilesBackupElapsed" >&2
          ${lib.optionalString (cfg.logLevel == "normal") ''
            printf '${cfg.colorRed}git said:${cfg.colorReset}\n' >&2
            printf '${cfg.colorRed}%s${cfg.colorReset}\n' "$dotfilesBackupPushOutput" >&2
          ''}
          printf '${cfg.colorRed}Public key, in case it needs (re-)adding as a deploy key with write${cfg.colorReset}\n' >&2
          printf '${cfg.colorRed}access (Settings -> Deploy keys):${cfg.colorReset}\n' >&2
          printf '${cfg.colorYellow}%s${cfg.colorReset}\n' "$(cat "${cfg.keyFile}.pub")" >&2
          printf '${cfg.colorGreen}note: this backup push is optional -- set vars.dotfilesBackup.enable = false in${cfg.colorReset}\n' >&2
          printf '${cfg.colorGreen}Nixos/modules/backup/dotfiles/default.nix to turn it off, or just ignore this${cfg.colorReset}\n' >&2
          printf '${cfg.colorGreen}error if you do not care about it right now.${cfg.colorReset}\n' >&2
          dotfilesBackupBorder "${cfg.colorRed}" >&2
          exit 1
        fi
      fi
    fi
  } ${lib.optionalString (cfg.logLevel == "silent") "> /dev/null 2>&1"}
  '';
}

