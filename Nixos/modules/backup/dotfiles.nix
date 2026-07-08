{ config, pkgs, lib, ... }:

# Variables
let

  # -----------------------------------------------------------------
  # CONFIGURATION
  # -----------------------------------------------------------------
  enable = false;

  # `nixos-rebuild test` runs this exact same activation script for real
  # (immediately, unfiltered) -- it just skips persisting the bootloader
  # entry. Only `switch` and an actual boot into this generation are
  # genuinely permanent; `test` is a throwaway trial that would otherwise
  # still push a real, permanent tag. true = skip pushing on `test` runs.
  skipOnTest = true;

  dotfilesPath = "/home/herauxvalle/Dotfiles";
  remoteUrl    = "git@github.com:HerauxValle/nixos.git";
  branch       = "main";

  # `date`(1) format string for the tag pushed whenever something actually
  # changes -- change this to reformat it, nothing else needs touching.
  # Dashes for time, dots for date, one underscore between the two groups
  # -- git tags reject spaces/colons/brackets outright (not a length
  # limit), hence not the more obvious "hh:mm:ss | [DD-MM-YYYY]" layout.
  tagDateFormat = "+%H-%M-%S_%d.%m.%Y";

  # Paths, relative to dotfilesPath, stripped from the snapshot before
  # committing -- never pushed anywhere.
  excludeFiles = [ "Claude/Global/config.json" "Shells/Fish/secrets.fish" ".envrc" ];

  # Git identity stamped on the snapshot commit (passed via -c, never
  # written to root's own global gitconfig).
  commitUserName  = "herauxvalle";
  commitUserEmail = "luca.schinkoethe@outlook.de";

  # true = reuse a persistent local clone across every activation and
  # skip the push entirely once nothing's actually changed -- lets git
  # send only the real diff, and skips the network completely on a
  # no-op rebuild. false = fresh throwaway repo + forced squash push
  # every time (no persistent history, always pushes).
  useRepoCache = true;

  # true = include git's actual error output in the red error block on
  # failure -- self-diagnosing, no need to reproduce the push by hand.
  logPushErrors = true;

  # Deploy key algorithm. No real reason to change this, but it's a
  # genuine independent choice (unlike keyComment below, which is derived,
  # not chosen) so it lives here rather than under DO NOT TOUCH.
  keyType = "ed25519";

  # ANSI color codes used in the bordered blocks below -- change these to
  # reskin the output. Empty string ("") for any of them disables that
  # color (still valid, just prints plain).
  colorRed    = ''\033[0;31m'';
  colorYellow = ''\033[0;33m'';
  colorGreen  = ''\033[0;32m'';
  colorReset  = ''\033[0m'';

  # Printed at the top/bottom of every warning/error/success block so
  # they're unmistakably one unit and clearly attributed to this module
  # amid the rest of the rebuild output.
  border = "[dotfiles-backup] ============================================";
  # -----------------------------------------------------------------

  # -----------------------------------------------------------------
  # DO NOT TOUCH
  # -----------------------------------------------------------------

  # Own subdirectory under the existing root-owned secrets convention
  # (see modules/security/sudo-keyfile.nix, Nixos/modules/system/users.nix)
  # so this doesn't bloat the flat /etc/nixos-secrets/ directory.
  secretsDir = "/etc/nixos-secrets/github";

  # Derived from dotfilesPath's own last path component (not an
  # independent literal) so it always matches reality.
  keyComment = "${baseNameOf dotfilesPath}-backup";

  # GitHub's own fixed API endpoint / error markers -- named here purely
  # for visibility rather than buried inline as string literals below.
  githubMetaApiUrl = "https://api.github.com/meta";
  githubSecretScanErrorCode = "GH013";
  hostKeyFailureMarker = "Host key verification failed";

  # This repo's own deploy key -- read-only for anyone but root, scoped to
  # pushing this one remote. Rotate any time by hand with `secrets
  # dotfiles` (Scripts/Secrets/cmd/dotfiles.sh); this activation script
  # also generates one itself if none exists yet (a safety net, same idea
  # as users.nix's password-hash fallback), it just never rotates an
  # existing one on its own -- rotation is exclusively a `secrets
  # dotfiles` action.
  keyFile = "${secretsDir}/dotfiles-backup";

  # Generated once (if missing), like the deploy key -- not refetched on
  # every activation, since that'd be a whole extra network round-trip
  # (separate DNS+TLS handshake to a different host from the push itself)
  # for no benefit in the common case where it's already correct. If
  # GitHub ever rotates their host key, the push-failure recovery below
  # detects that specific failure and refreshes it automatically.
  knownHostsFile = "${secretsDir}/known_hosts";

  gitSshCommand = "${pkgs.openssh}/bin/ssh -i ${keyFile} -o UserKnownHostsFile=${knownHostsFile} -o StrictHostKeyChecking=yes";

  repoCache = "${secretsDir}/repo-cache";

  # Refreshes known_hosts from GitHub's /meta API -- trust comes from that
  # HTTPS request's own TLS/CA chain (the same one every other HTTPS fetch
  # on this system already relies on), not from SSH trust-on-first-use.
  # Used both for the initial bootstrap and the reactive recovery below.
  refreshKnownHosts = ''
    tmpKnownHosts="$(mktemp)"
    if ${pkgs.curl}/bin/curl -fsS ${githubMetaApiUrl} 2>/dev/null \
         | ${pkgs.jq}/bin/jq -r '.ssh_keys[] | select(startswith("${keyType} ")) | "github.com " + .' \
         > "$tmpKnownHosts" 2>/dev/null \
       && [ -s "$tmpKnownHosts" ]; then
      mv "$tmpKnownHosts" "${knownHostsFile}"
      chmod 644 "${knownHostsFile}"
      chown root:root "${knownHostsFile}"
    else
      rm -f "$tmpKnownHosts"
    fi
  '';

  # One push attempt, capturing real stderr (needed for the reactive
  # recovery checks below and for logPushErrors) without losing the exit
  # code -- `$(cmd 2>&1 1>/dev/null)` swaps the streams so only stderr
  # lands in the variable while `$?` still reflects the actual push.
  gitPush = force: ''
    ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" -c core.sshCommand="${gitSshCommand}" push -q ${force} "${remoteUrl}" "${branch}" 2>&1 1>/dev/null
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
lib.mkIf enable {

  system.activationScripts.dotfilesBackup.text = ''
    ${lib.optionalString skipOnTest ''
      if [ "''${NIXOS_ACTION:-}" = "test" ]; then
        exit 0
      fi
    ''}
    dotfilesBackupStart="$(date +%s.%N)"
    mkdir -p "${secretsDir}"
    chmod 700 "${secretsDir}"
    chown root:root "${secretsDir}"

    if [ ! -f "${keyFile}" ]; then
      ${pkgs.openssh}/bin/ssh-keygen -q -t ${keyType} -N "" -C "${keyComment}" -f "${keyFile}"
      chmod 600 "${keyFile}"
      chmod 644 "${keyFile}.pub"
      chown root:root "${keyFile}" "${keyFile}.pub"
      printf '${colorRed}${border}${colorReset}\n' >&2
      printf '${colorRed}warning: no deploy key existed -- generated a new one at ${keyFile}.${colorReset}\n' >&2
      printf '${colorRed}Add the public key below to the Dotfiles repo on GitHub (Settings -> Deploy${colorReset}\n' >&2
      printf '${colorRed}keys -> Add deploy key, tick "Allow write access") -- nothing will push${colorReset}\n' >&2
      printf '${colorRed}until you do:${colorReset}\n' >&2
      printf '${colorYellow}%s${colorReset}\n' "$(cat "${keyFile}.pub")" >&2
      printf '${colorGreen}note: this backup push is optional -- set enable = false in${colorReset}\n' >&2
      printf '${colorGreen}Nixos/modules/backup/dotfiles.nix to turn it off, or just ignore this${colorReset}\n' >&2
      printf '${colorGreen}warning if you do not care about it right now.${colorReset}\n' >&2
      printf '${colorRed}${border}${colorReset}\n' >&2
    fi

    if [ ! -f "${knownHostsFile}" ]; then
      ${refreshKnownHosts}
    fi

    if [ -f "${keyFile}" ]; then
      tag="$(date "${tagDateFormat}")"
      dotfilesBackupChanged=1

      ${if useRepoCache then ''
        if [ ! -d "${repoCache}/.git" ]; then
          ${pkgs.git}/bin/git -c safe.directory="${repoCache}" init -q -b "${branch}" "${repoCache}"
          chmod 700 "${repoCache}"
        fi
        ${pkgs.rsync}/bin/rsync -a --delete --exclude=.git "${dotfilesPath}/" "${repoCache}/"
        ${lib.concatMapStringsSep "\n        " (f: ''rm -rf "${repoCache}/${f}"'') excludeFiles}
        ${pkgs.git}/bin/git -C "${repoCache}" -c safe.directory="${repoCache}" add -A
        if ${pkgs.git}/bin/git -C "${repoCache}" -c safe.directory="${repoCache}" diff --cached --quiet; then
          dotfilesBackupChanged=0
        else
          ${pkgs.git}/bin/git -C "${repoCache}" -c safe.directory="${repoCache}" -c user.name="${commitUserName}" -c user.email="${commitUserEmail}" commit -q -m "$tag"
        fi
        repoPath="${repoCache}"
        pushForce=""
      '' else ''
        if [ -d "${repoCache}" ]; then
          rm -rf "${repoCache}"
        fi
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        cp -a "${dotfilesPath}/." "$tmp/" 2>/dev/null || true
        rm -rf "$tmp/.git"
        ${lib.concatMapStringsSep "\n        " (f: ''rm -rf "$tmp/${f}"'') excludeFiles}
        ${pkgs.git}/bin/git -c safe.directory="$tmp" init -q -b "${branch}" "$tmp"
        ${pkgs.git}/bin/git -C "$tmp" -c safe.directory="$tmp" add -A
        ${pkgs.git}/bin/git -C "$tmp" -c safe.directory="$tmp" -c user.name="${commitUserName}" -c user.email="${commitUserEmail}" commit -q -m "$tag" || true
        repoPath="$tmp"
        pushForce="-f"
      ''}

      if [ "$dotfilesBackupChanged" = "1" ]; then
        pushOutput="$(${gitPush "$pushForce"})"
        pushRc=$?

        # Each recovery below fires only on its own specific, detected
        # failure signature -- zero cost when the push just works, which
        # is the common case. Bounded to exactly one retry each; a retry
        # that also fails falls through to the real error below, not
        # another attempt.
        if [ $pushRc -ne 0 ] && printf '%s' "$pushOutput" | grep -q "${hostKeyFailureMarker}"; then
          ${refreshKnownHosts}
          pushOutput="$(${gitPush "$pushForce"})"
          pushRc=$?
        fi

        ${lib.optionalString useRepoCache ''
          if [ $pushRc -ne 0 ]; then
            pushOutput="$(${gitPush "-f"})"
            pushRc=$?
          fi

          if [ $pushRc -ne 0 ] && printf '%s' "$pushOutput" | grep -q "${githubSecretScanErrorCode}"; then
            ( cd "${repoCache}" && ${pkgs.git-filter-repo}/bin/git-filter-repo --force ${lib.concatMapStringsSep " " (f: ''--path "${f}"'') excludeFiles} --invert-paths ) || true
            ${pkgs.rsync}/bin/rsync -a --delete --exclude=.git "${dotfilesPath}/" "${repoCache}/"
            ${lib.concatMapStringsSep "\n            " (f: ''rm -rf "${repoCache}/${f}"'') excludeFiles}
            ${pkgs.git}/bin/git -C "${repoCache}" -c safe.directory="${repoCache}" add -A
            ${pkgs.git}/bin/git -C "${repoCache}" -c safe.directory="${repoCache}" -c user.name="${commitUserName}" -c user.email="${commitUserEmail}" commit -q --allow-empty -m "$tag"
            pushOutput="$(${gitPush "-f"})"
            pushRc=$?
          fi
        ''}

        dotfilesBackupElapsed="$(${pkgs.gawk}/bin/awk -v s="$dotfilesBackupStart" -v e="$(date +%s.%N)" 'BEGIN{printf "%.2f", e-s}')"

        if [ $pushRc -eq 0 ]; then
          ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" tag "$tag"
          ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" -c core.sshCommand="${gitSshCommand}" push -q "${remoteUrl}" "$tag" 2>/dev/null || echo "warning: dotfiles-backup pushed ${branch} but the tag push failed" >&2
          printf '${colorGreen}${border}${colorReset}\n'
          printf '${colorGreen}successfully pushed %s to %s (took %ss)${colorReset}\n' "$tag" "${remoteUrl}" "$dotfilesBackupElapsed"
          printf '${colorGreen}${border}${colorReset}\n'
        else
          printf '${colorRed}${border}${colorReset}\n' >&2
          printf '${colorRed}error: failed to push %s to %s (took %ss).${colorReset}\n' "${branch}" "${remoteUrl}" "$dotfilesBackupElapsed" >&2
          ${lib.optionalString logPushErrors ''
            printf '${colorRed}git said:${colorReset}\n' >&2
            printf '${colorRed}%s${colorReset}\n' "$pushOutput" >&2
          ''}
          printf '${colorRed}Public key, in case it needs (re-)adding as a deploy key with write${colorReset}\n' >&2
          printf '${colorRed}access (Settings -> Deploy keys):${colorReset}\n' >&2
          printf '${colorYellow}%s${colorReset}\n' "$(cat "${keyFile}.pub")" >&2
          printf '${colorGreen}note: this backup push is optional -- set enable = false in${colorReset}\n' >&2
          printf '${colorGreen}Nixos/modules/backup/dotfiles.nix to turn it off, or just ignore this${colorReset}\n' >&2
          printf '${colorGreen}error if you do not care about it right now.${colorReset}\n' >&2
          printf '${colorRed}${border}${colorReset}\n' >&2
          exit 1
        fi
      fi
    fi
  '';

}
