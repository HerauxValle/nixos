{ config, pkgs, lib, ... }:

let
  cfg = config.vars.dotfilesBackup;

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
lib.mkIf cfg.enable {

  system.activationScripts.dotfilesBackup.text = ''
    ${lib.optionalString cfg.skipOnTest ''
      if [ "''${NIXOS_ACTION:-}" = "test" ]; then
        exit 0
      fi
    ''}
  {
    dotfilesBackupBorder() {
      printf '%b${cfg.border}${cfg.colorReset}\n' "$1"
    }

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

      ${if cfg.useRepoCache then ''
        if [ ! -d "${cfg.repoCache}/.git" ]; then
          ${pkgs.git}/bin/git -c safe.directory="${cfg.repoCache}" init -q -b "${cfg.branch}" "${cfg.repoCache}"
        fi
        chmod 700 "${cfg.repoCache}"
        ${pkgs.rsync}/bin/rsync -a --delete --exclude=.git "${cfg.dotfilesPath}/" "${cfg.repoCache}/"
        ${lib.concatMapStringsSep "\n        " (f: ''rm -rf "${cfg.repoCache}/${f}"'') cfg.excludeFiles}
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
            ( cd "${cfg.repoCache}" && ${pkgs.git-filter-repo}/bin/git-filter-repo --force ${lib.concatMapStringsSep " " (f: ''--path "${f}"'') cfg.excludeFiles} --invert-paths ) || true
            ${pkgs.rsync}/bin/rsync -a --delete --exclude=.git "${cfg.dotfilesPath}/" "${cfg.repoCache}/"
            ${lib.concatMapStringsSep "\n            " (f: ''rm -rf "${cfg.repoCache}/${f}"'') cfg.excludeFiles}
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
