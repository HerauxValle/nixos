# &desc: "Sudo keyfile activation script -- idempotent generate/adopt keyfile, hash+conf write, self-test read-back via the raw checker."

{ pkgs, cfg, checker }:

# Idempotent, mirrors users.nix's own hashedPasswordFile bootstrap
# pattern: only ever generates the secret if it isn't already there,
# never regenerates/clobbers an existing one. To rotate, delete
# ${cfg.hashFile} and ${cfg.confFile} (and the keyfile itself) and rebuild.
''
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
''
