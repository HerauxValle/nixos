# &desc: "Passwordless sudo via keyfile logic -- setuid-root PAM checker runs on every sudo, checks keyfile hash, fast-fails to passphrase on error."

{ config, pkgs, lib, ... }:

let
  cfg = config.vars.security.sudoKeyfile;

  # The setuid-root wrapper's installed path -- this, not the raw
  # ${checker}/bin path, is what PAM and the self-test must actually
  # invoke, since only this one runs with root privilege.
  wrapperPath = "${config.security.wrapperDir}/sudo-keyfile-check";

  # Runs on EVERY "sudo" PAM auth attempt (interactive, smg/pmg background
  # jobs, the sudo broker's own re-exec -- all of it, unscoped by design).
  # Must fail fast, never hang: exit 1 for any missing/mismatched/erroring
  # step just falls through to the normal password prompt (this rule is
  # `sufficient`, not `required` -- see the pam rule below).
  #
  # runtimeInputs wires the exact fs tools this needs directly into the
  # script's PATH via the Nix closure -- no `command -v` presence checks
  # needed anywhere, unlike an imperative install this would otherwise be
  # a runtime concern.
  #
  # PAM's auth phase invokes this as the calling user (uid 1000 here), not
  # root -- that's the whole point of an auth check, it can't already have
  # the privilege it's deciding whether to grant. Reading a raw block
  # device and root-owned secret files needs root though, so this alone
  # would always fail (confirmed: debugged a live failure down to exactly
  # this). Fixed below via security.wrappers, not by weakening this to run
  # unprivileged -- same setuid-root approach NixOS already uses for sudo
  # and ping themselves.
  checker = pkgs.writeShellApplication {
    name = "sudo-keyfile-check";
    runtimeInputs = [
      pkgs.e2fsprogs   # debugfs   -- ext2/3/4, no mount
      pkgs.mtools      # mcopy     -- FAT/FAT32, no mount
      pkgs.ntfs3g      # ntfscat   -- NTFS, no mount
      pkgs.btrfs-progs # restore   -- btrfs, no mount
      pkgs.util-linux  # blkid, mount, umount
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      [ -f "${cfg.confFile}" ] || exit 1
      [ -f "${cfg.hashFile}" ] || exit 1

      # shellcheck source=/dev/null
      source "${cfg.confFile}"
      : "''${IDENT_TYPE:?}" "''${IDENT_VALUE:?}" "''${REL_PATH:?}"

      dev="/dev/disk/by-''${IDENT_TYPE}/''${IDENT_VALUE}"
      [ -e "$dev" ] || exit 1

      fstype="$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)"
      [ -n "$fstype" ] || exit 1

      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT

      content=""
      case "$fstype" in
        ext2|ext3|ext4)
          content="$(debugfs -R "cat $REL_PATH" "$dev" 2>/dev/null || true)"
          ;;
        vfat|fat|msdos)
          content="$(mcopy -n -i "$dev" "::$REL_PATH" - 2>/dev/null || true)"
          ;;
        ntfs)
          content="$(ntfscat -f "$dev" "$REL_PATH" 2>/dev/null || true)"
          ;;
        btrfs)
          if btrfs restore --path-regex "^$REL_PATH\$" "$dev" "$tmpdir" >/dev/null 2>&1; then
            f="$tmpdir/$REL_PATH"
            [ -f "$f" ] && content="$(cat "$f")"
          fi
          ;;
        *)
          # No no-mount extractor for this fs (exfat/xfs/zfs/...) -- quick
          # mount-then-read fallback instead. No retry loop here (unlike
          # Casket's boot-race handling) since this runs on every sudo
          # call: absent/slow device must fail fast, not hang the prompt.
          mnt="$tmpdir/mnt"
          mkdir -p "$mnt"
          if mount -o ro "$dev" "$mnt" >/dev/null 2>&1; then
            f="$mnt/$REL_PATH"
            [ -f "$f" ] && content="$(cat "$f")"
            umount "$mnt" >/dev/null 2>&1 || true
          fi
          ;;
      esac

      [ -n "$content" ] || exit 1

      actual_hash="$(printf '%s' "$content" | sha256sum | cut -d' ' -f1)"
      stored_hash="$(cat "${cfg.hashFile}")"
      [ "$actual_hash" = "$stored_hash" ] || exit 1
      exit 0
    '';
  };

  # security.wrappers' setuid stub calls execve() on its `source` file
  # directly. If that's a shebang script (which writeShellApplication's
  # output always is), the kernel's binfmt_script handler strips the
  # elevated privilege before running it -- this is a hard, deliberate
  # Linux restriction against the classic setuid-script vulnerability
  # class, applied unconditionally, even when the calling process is
  # *already* root via its own (separate) setuid bit.
  #
  # Fix: this tiny compiled stub is what actually gets wrapped instead.
  # It execve()s the real bash binary directly (a plain ELF, no shebang
  # involved at the kernel level) with the checker script as bash's own
  # argument -- bash then just reads/interprets that file as data, never
  # triggering binfmt_script.
  #
  # That alone still wasn't enough (confirmed live: euid was still 1000
  # inside the script) -- bash itself has a SEPARATE safety behavior:
  # whenever real uid != effective uid at startup (exactly this setuid
  # scenario: ruid=1000 from the calling user, euid=0 from the setuid
  # wrapper), bash silently resets its effective uid back to the real uid
  # unless started with `-p`. `sudo <stub>` alone "worked" in testing only
  # because real sudo sets ruid=euid=0 (no mismatch, so the auto-drop
  # never triggers there) -- masking this exact issue.
  checkerStub = pkgs.writeCBin "sudo-keyfile-check-stub" ''
    #include <unistd.h>
    int main(void) {
      execl("${pkgs.bash}/bin/bash", "bash", "-p", "${checker}/bin/sudo-keyfile-check", (char *)NULL);
      return 1;
    }
  '';

in

# Sudo keyfile auth
lib.mkIf cfg.enable {

  # Idempotent, mirrors users.nix's own hashedPasswordFile bootstrap
  # pattern: only ever generates the secret if it isn't already there,
  # never regenerates/clobbers an existing one. To rotate, delete
  # ${cfg.hashFile} and ${cfg.confFile} (and the keyfile itself) and rebuild.
  system.activationScripts.sudoKeyfile.text = ''
    mkdir -p "${cfg.secretsDir}"
    chmod 700 "${cfg.secretsDir}"

    if [ -f "${cfg.hashFile}" ] && [ -f "${cfg.confFile}" ]; then
      : # already generated -- leave it alone
    else
      PARENT="$(dirname "${cfg.keyfilePath}")"
      if [ ! -d "$PARENT" ]; then
        echo "warning: sudo keyfile path's parent dir ($PARENT) doesn't exist -- is the device mounted? Skipping keyfile generation this activation; will retry next rebuild." >&2
      else
        if [ -f "${cfg.keyfilePath}" ]; then
          # Adopt whatever's already there instead of clobbering it --
          # matters if this is a pre-existing keyfile (previous install,
          # placed there by hand, shared with something else) rather
          # than a fresh device.
          SECRET="$(cat "${cfg.keyfilePath}")"
          echo "Existing keyfile found at ${cfg.keyfilePath} -- registering it as-is (not overwriting)."
        else
          SECRET="$(head -c32 /dev/urandom | base64)"
          printf '%s' "$SECRET" > "${cfg.keyfilePath}"
          chmod 600 "${cfg.keyfilePath}"
          echo "No keyfile found at ${cfg.keyfilePath} -- generated a new one."
        fi

        # The keyfile write above went through the normal mounted
        # filesystem (page cache); the self-test below reads it back
        # straight off the raw block device (debugfs/mtools/etc, bypassing
        # that cache). Without a sync in between, the raw read can see a
        # stale image that doesn't have the new file yet.
        sync

        HASH="$(printf '%s' "$SECRET" | sha256sum | cut -d' ' -f1)"
        printf '%s\n' "$HASH" > "${cfg.hashFile}"
        chmod 600 "${cfg.hashFile}"
        chown root:root "${cfg.hashFile}"
        unset SECRET HASH

        DEV="$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE --target "$PARENT")"
        LABEL="$(${pkgs.util-linux}/bin/blkid -o value -s LABEL "$DEV" 2>/dev/null || true)"
        if [ -n "$LABEL" ]; then
          IDENT_TYPE=label
          IDENT_VALUE="$LABEL"
        else
          IDENT_TYPE=uuid
          IDENT_VALUE="$(${pkgs.util-linux}/bin/blkid -o value -s UUID "$DEV" 2>/dev/null || true)"
        fi
        MOUNTPOINT="$(${pkgs.util-linux}/bin/findmnt -n -o TARGET --target "$PARENT")"
        REL_PATH="${cfg.keyfilePath}"
        REL_PATH="''${REL_PATH#"$MOUNTPOINT"}"

        cat > "${cfg.confFile}" <<EOF
IDENT_TYPE=$IDENT_TYPE
IDENT_VALUE=$IDENT_VALUE
REL_PATH=$REL_PATH
EOF
        chmod 600 "${cfg.confFile}"
        chown root:root "${cfg.confFile}"

        # Prove the whole pipeline actually works right now -- device
        # lookup, fs-type detection, no-mount extraction, hash compare --
        # rather than trusting it silently. A registration that can't be
        # read back is worse than no registration: sudo would just always
        # fall through to the password prompt with no indication why.
        # Calls the raw (unwrapped) checker, not the setuid wrapper: this
        # activation script already runs as root, and the wrapper itself
        # may not exist yet this same rebuild (it's created by a systemd
        # service that (re)starts AFTER activation scripts run, not
        # something activation-script ordering can depend on).
        if "${checker}/bin/sudo-keyfile-check"; then
          echo "Sudo keyfile registered and verified usable at ${cfg.keyfilePath}."
        else
          echo "WARNING: sudo keyfile registered at ${cfg.keyfilePath}, but the verification read-back FAILED -- keyfile-based sudo auth will NOT work (always falls through to password) until this is fixed. Check that the detected filesystem type is supported (ext2/3/4, FAT, NTFS, btrfs -- others rely on a mount fallback) and that the device is reachable at this path." >&2
        fi
      fi
    fi
  '';

  # Setuid-root wrapper around the (otherwise unprivileged) checker --
  # same mechanism NixOS uses for sudo/ping themselves. Required because
  # PAM's auth phase invokes this as the calling user, but reading the raw
  # block device and the root-owned hash/conf files needs real root.
  security.wrappers.sudo-keyfile-check = {
    source = "${checkerStub}/bin/sudo-keyfile-check-stub";
    owner = "root";
    group = "root";
    setuid = true;
  };

  security.pam.services.sudo.rules.auth.keyfile = {
    # Just before the standard `unix` (password) rule, so a present,
    # valid keyfile skips the password prompt entirely -- but a missing/
    # wrong one always falls through to it (`sufficient`, not
    # `required`; unix itself is untouched).
    order = config.security.pam.services.sudo.rules.auth.unix.order - 50;
    control = "sufficient";
    modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
    args = [ "quiet" wrapperPath ];
  };
}
