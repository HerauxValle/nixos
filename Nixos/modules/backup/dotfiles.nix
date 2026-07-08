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

  # `date`(1) format string for the tag pushed on every activation --
  # change this to reformat it, nothing else needs touching. Git tags
  # can't contain spaces, colons, or brackets (git rejects them outright,
  # not a length limit), hence dashes/dots/underscore instead of the more
  # obvious "hh:mm:ss | [DD-MM-YYYY]" layout. Dashes for time, dots for
  # date, one underscore between the two groups -- so the two halves are
  # visually distinct at a glance, not just one long dash-separated blob.
  tagDateFormat = "+%H-%M-%S_%d.%m.%Y";

  # Paths, relative to dotfilesPath, stripped from the snapshot before
  # committing -- never pushed anywhere.
  excludeFiles = [ "Claude/Global/config.json" ];

  # Git identity stamped on the snapshot commit (passed via -c, never
  # written to root's own global gitconfig).
  commitUserName  = "herauxvalle";
  commitUserEmail = "luca.schinkoethe@outlook.de";

  # true = reuse a persistent local clone across every activation instead
  # of a fresh throwaway repo each time -- lets git send only the real
  # diff on push instead of the whole snapshot's content every single
  # run. A brand new orphan commit each run (false) has zero shared
  # history with the remote, so git can't tell what it already has and
  # has to resend everything -- that's what makes every push take ~5s
  # regardless of how little actually changed. false also force-pushes a
  # fresh squashed commit each time (no real history); true keeps a real,
  # growing history and pushes normally (no force). Switching this to
  # false purges any existing cache below first -- cheap, it's a local
  # delete, no network involved.
  useRepoCache = true;
  # -----------------------------------------------------------------

  # -----------------------------------------------------------------
  # DO NOT TOUCH
  # -----------------------------------------------------------------

  # Own subdirectory under the existing root-owned secrets convention
  # (see modules/security/sudo-keyfile.nix, Nixos/modules/system/users.nix)
  # so this doesn't bloat the flat /etc/nixos-secrets/ directory.
  secretsDir = "/etc/nixos-secrets/github";

  # This repo's own deploy key -- read-only for anyone but root, scoped to
  # pushing this one remote. Rotate any time by hand with `secrets
  # dotfiles` (Scripts/Secrets/cmd/dotfiles.sh); this activation script
  # also generates one itself if none exists yet (a safety net, same idea
  # as users.nix's password-hash fallback), it just never rotates an
  # existing one on its own -- rotation is exclusively a `secrets
  # dotfiles` action.
  keyFile = "${secretsDir}/dotfiles-backup";

  # Refreshed from GitHub's own /meta API on every activation (see below)
  # instead of a hardcoded key -- trust comes from that HTTPS request's own
  # TLS/CA chain (the same one every other HTTPS fetch on this system
  # already relies on), not from SSH trust-on-first-use, and it can't go
  # stale if GitHub ever rotates their host key.
  knownHostsFile = "${secretsDir}/known_hosts";

  gitSshCommand = "${pkgs.openssh}/bin/ssh -i ${keyFile} -o UserKnownHostsFile=${knownHostsFile} -o StrictHostKeyChecking=yes";

  repoCache = "${secretsDir}/repo-cache";

in

# Dotfiles GitHub backup
#
# Runs entirely as a system.activationScripts entry -- no systemd service
# or timer sits around in the background. That also means this fires on
# EVERY activation of this generation, not only an explicit `nixos-rebuild
# switch`/`pacnix rebuild` -- a plain reboot re-activates the current
# generation too, so it pushes a fresh snapshot then as well. The tag is
# timestamp-based specifically so that's fine: every activation is its own
# permanent, independently timestamped snapshot, same spirit as NixOS
# handing out a new generation number every time regardless of whether
# anything actually changed.
#
# Independent of Scripts/Secrets on purpose: the key-generation fallback
# below is duplicated (not shared) with Scripts/Secrets/cmd/dotfiles.sh,
# same relationship users.nix's own inline password-hash fallback has with
# Scripts/Secrets/cmd/passwd.sh -- an activation script depending on a
# script living inside the checkout it's activating is a fragile ordering
# problem to introduce for no real benefit.
lib.mkIf enable {

  system.activationScripts.dotfilesBackup.text = ''
    ${lib.optionalString skipOnTest ''
      if [ "''${NIXOS_ACTION:-}" = "test" ]; then
        exit 0
      fi
    ''}
    mkdir -p "${secretsDir}"
    chmod 700 "${secretsDir}"
    chown root:root "${secretsDir}"

    tmpKnownHosts="$(mktemp)"
    if ${pkgs.curl}/bin/curl -fsS https://api.github.com/meta 2>/dev/null \
         | ${pkgs.jq}/bin/jq -r '.ssh_keys[] | select(startswith("ssh-ed25519 ")) | "github.com " + .' \
         > "$tmpKnownHosts" 2>/dev/null \
       && [ -s "$tmpKnownHosts" ]; then
      mv "$tmpKnownHosts" "${knownHostsFile}"
      chmod 644 "${knownHostsFile}"
      chown root:root "${knownHostsFile}"
    else
      rm -f "$tmpKnownHosts"
    fi

    if [ ! -f "${keyFile}" ]; then
      ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C "dotfiles-backup" -f "${keyFile}"
      chmod 600 "${keyFile}"
      chmod 644 "${keyFile}.pub"
      chown root:root "${keyFile}" "${keyFile}.pub"
      printf '\033[0;31m[dotfiles-backup] ============================================\033[0m\n' >&2
      printf '\033[0;31mwarning: no deploy key existed -- generated a new one at ${keyFile}.\033[0m\n' >&2
      printf '\033[0;31mAdd the public key below to the Dotfiles repo on GitHub (Settings -> Deploy\033[0m\n' >&2
      printf '\033[0;31mkeys -> Add deploy key, tick "Allow write access") -- nothing will push\033[0m\n' >&2
      printf '\033[0;31muntil you do:\033[0m\n' >&2
      printf '\033[0;33m%s\033[0m\n' "$(cat "${keyFile}.pub")" >&2
      printf '\033[0;32mnote: this backup push is optional -- set enable = false in\033[0m\n' >&2
      printf '\033[0;32mNixos/modules/backup/dotfiles.nix to turn it off, or just ignore this\033[0m\n' >&2
      printf '\033[0;32mwarning if you do not care about it right now.\033[0m\n' >&2
      printf '\033[0;31m[dotfiles-backup] ============================================\033[0m\n' >&2
    fi

    if [ -f "${keyFile}" ]; then
      tag="$(date "${tagDateFormat}")"

      ${if useRepoCache then ''
        if [ ! -d "${repoCache}/.git" ]; then
          ${pkgs.git}/bin/git -c safe.directory="${repoCache}" init -q -b "${branch}" "${repoCache}"
          chmod 700 "${repoCache}"
        fi
        ${pkgs.rsync}/bin/rsync -a --delete --exclude=.git "${dotfilesPath}/" "${repoCache}/"
        ${lib.concatMapStringsSep "\n        " (f: ''rm -rf "${repoCache}/${f}"'') excludeFiles}
        repoPath="${repoCache}"
        commitArgs="-q --allow-empty"
        pushForce=""
        # The remote can end up not sharing history with this cache for
        # reasons outside this script's control (repo deleted/recreated,
        # manually force-pushed elsewhere, this is a brand new cache while
        # the remote already has older content, etc). This backup is
        # always meant to be authoritative over that remote, so retry once
        # with -f rather than treating a plain divergence as a hard
        # failure -- only a retry that ALSO fails (e.g. auth) is a real
        # error.
        retryForce="-f"
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
        repoPath="$tmp"
        commitArgs="-q"
        pushForce="-f"
        retryForce=""
      ''}

      ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" add -A
      ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" -c user.name="${commitUserName}" -c user.email="${commitUserEmail}" commit $commitArgs -m "$tag" || true

      pushOk=0
      if ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" -c core.sshCommand="${gitSshCommand}" push -q $pushForce "${remoteUrl}" "${branch}" 2>/dev/null; then
        pushOk=1
      elif [ -n "$retryForce" ] && ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" -c core.sshCommand="${gitSshCommand}" push -q $retryForce "${remoteUrl}" "${branch}" 2>/dev/null; then
        pushOk=1
      fi

      if [ "$pushOk" = 1 ]; then
        ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" tag "$tag"
        ${pkgs.git}/bin/git -C "$repoPath" -c safe.directory="$repoPath" -c core.sshCommand="${gitSshCommand}" push -q "${remoteUrl}" "$tag" 2>/dev/null || echo "warning: dotfiles-backup pushed ${branch} but the tag push failed" >&2
        printf '\033[0;32m[dotfiles-backup] ============================================\033[0m\n'
        printf '\033[0;32msuccessfully pushed %s to %s\033[0m\n' "$tag" "${remoteUrl}"
        printf '\033[0;32m[dotfiles-backup] ============================================\033[0m\n'
      else
        printf '\033[0;31m[dotfiles-backup] ============================================\033[0m\n' >&2
        printf '\033[0;31merror: failed to push %s to %s.\033[0m\n' "${branch}" "${remoteUrl}" >&2
        printf '\033[0;31mThe deploy key may not be registered on GitHub yet (Settings -> Deploy\033[0m\n' >&2
        printf '\033[0;31mkeys -> Add deploy key, tick "Allow write access"). Public key:\033[0m\n' >&2
        printf '\033[0;33m%s\033[0m\n' "$(cat "${keyFile}.pub")" >&2
        printf '\033[0;32mnote: this backup push is optional -- set enable = false in\033[0m\n' >&2
        printf '\033[0;32mNixos/modules/backup/dotfiles.nix to turn it off, or just ignore this\033[0m\n' >&2
        printf '\033[0;32merror if you do not care about it right now.\033[0m\n' >&2
        printf '\033[0;31m[dotfiles-backup] ============================================\033[0m\n' >&2
        exit 1
      fi
    fi
  '';

}
