#!/usr/bin/env bash
cat <<'EOF'
usage: secrets <command>

  passwd
      (Re)set the account password's hash file at
      /etc/nixos-secrets/herauxvalle-password.hash. A rebuild deploys it.

  dotfiles
      (Re)generate the deploy key used to push the Dotfiles backup to
      GitHub, at /etc/nixos-secrets/github/dotfiles-backup. Prints the new
      public key to register on GitHub yourself -- no rebuild needed.

  github add <auth|sign>
      (Re)generate one of your two personal GitHub SSH keys, at
      /etc/nixos-secrets/github/<auth|sign> -- independent of each other,
      generating one never touches the other. auth is used for git
      clone/push over SSH, sign for commit signing. Prints the new public
      key to register on GitHub yourself (Settings -> SSH and GPG keys).
      Run 'pacnix rebuild' after -- Nixos/modules/security/github-keys.nix
      deploys it into ~/.ssh and wires it up, which needs a rebuild
      (unlike 'dotfiles' above, this one isn't read straight from
      /etc/nixos-secrets by anything, so nothing uses it until deployed).

  github rem <auth|sign>
      Deletes that key from /etc/nixos-secrets/github. Run 'pacnix rebuild'
      after to also remove the deployed ~/.ssh copy and its wiring. Delete
      the matching public key from GitHub yourself too -- it keeps working
      there otherwise.

  self-hosted <name>
      (Re)set env-var secrets (API tokens etc) for a self-hosted service
      at /etc/nixos-secrets/self-hosted/<name>/tokens.env. Prompts for
      KEY=VALUE pairs, existing keys keep their value unless re-entered.
      Restart the service to deploy a changed value -- no rebuild needed.

  qbittorrent
      Print the live WebUI login (Username/Password_PBKDF2/APIKey) from
      qBittorrent.conf, ready to paste into config/self-hosted/
      qbittorrent.nix's extraServerConfig. Read-only, writes nothing --
      set a real password via the WebUI first (Options -> Web UI), then
      run this to capture it. A rebuild deploys the pasted value.
EOF
