{ config, pkgs, lib, ... }:

{
  # false = user accounts (passwords especially) are fully declarative:
  # hashedPassword below is re-applied on EVERY rebuild, overriding any
  # `passwd`-based change made in between -- the tradeoff being `passwd`
  # itself no longer has any lasting effect. Default is true (only sets
  # the password the first time an account is created, then leaves it
  # alone forever after -- which is what silently made `changeme` keep
  # working after the hash was first added here).
  users.mutableUsers = false;

  # SAFETY NET -- hit this exact scenario for real once already: with
  # mutableUsers = false, if hashedPasswordFile below points at a file that
  # doesn't exist, NixOS's own activation script (update-users-groups.pl)
  # does NOT fall back to anything -- it warns and leaves the account
  # LOCKED ("!" in /etc/shadow, matching no password at all, not "no
  # password required"). initialPassword/initialHashedPassword don't help
  # here either: NixOS only consults those for an account being created
  # for the very first time, not an already-existing one like this.
  #
  # So: ensure the file always exists before NixOS's own "users" activation
  # script ever runs, falling back to a known password (changeme) if it's
  # ever missing, rather than silently locking the account. Prepended via
  # mkBefore into the same activation script text NixOS's own module
  # defines (system.activationScripts.users), not a separate script -- so
  # ordering relative to it is guaranteed, not left to chance.
  system.activationScripts.users.text = lib.mkBefore ''
    HASH_FILE="${config.vars.system.users.hashFile}"
    if [ ! -f "$HASH_FILE" ]; then
      mkdir -p "$(dirname "$HASH_FILE")"
      chmod 700 "$(dirname "$HASH_FILE")"
      # Static string, not computed here, so this has no runtime dependency
      # on mkpasswd existing at activation time. Quoted heredoc (not
      # `echo '...'`) so nothing here needs shell-escaping regardless of
      # the hash's content. Value itself lives in config.vars.system.users.fallbackHash.
      cat > "$HASH_FILE" <<'HASHEOF'
${config.vars.system.users.fallbackHash}
HASHEOF
      chmod 600 "$HASH_FILE"
      chown root:root "$HASH_FILE"
      echo "warning: $HASH_FILE was missing -- wrote a fallback hash (password: changeme). Run 'secrets passwd' to set a real one, then rebuild." >&2
    fi
  '';

  users.users.${config.vars.identity.username} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "immich"
      "qbittorrent"
      "kvm" # Claude Desktop's Cowork feature spins up a local KVM sandbox
    ];

    # initialPassword = "changeme";  # one-time bootstrap only, from before
    #                                # mutableUsers = false -- irrelevant now
    #                                # that hashedPassword below is always
    #                                # authoritative regardless.

    # hashedPassword = "...";  # Works, but bakes the hash directly into the
    #                          # Nix config, which ends up copied into the
    #                          # world-readable /nix/store. hashedPasswordFile
    #                          # below keeps it in a normal root-owned file
    #                          # instead. Generate a value for this field
    #                          # with: mkpasswd -m sha-512 "<password>"

    # Re-applied on every rebuild (mutableUsers = false above) -- this file's
    # CONTENT (not this path) is what's authoritative. Also your sudo
    # password: sudo just re-checks your account's own password via PAM,
    # there's no separate one. Written by ./install.sh (prompts for a
    # password, hashes it, writes it here as root:root, 600) -- run that
    # first, this path won't exist otherwise.
    hashedPasswordFile = config.vars.system.users.hashFile;

    # password = "plaintext";  # Also exists, but stores the literal password
    #                          # readably in the Nix store -- no real reason
    #                          # to use this over hashedPasswordFile above.

    shell = pkgs.fish;
  };
}
