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
