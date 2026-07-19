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

  github add <auth|sign|token>
      (Re)generate/(re)set one of your personal GitHub credentials, at
      /etc/nixos-secrets/github/<auth|sign|api-token> -- independent of
      each other, setting one never touches the others. auth is used for
      git clone/push over SSH, sign for commit signing, token is a
      GitHub personal access token (repo scope) used by `pacnix github
      release` to create/delete GitHub Releases. auth/sign print the new
      public key to register on GitHub yourself (Settings -> SSH and GPG
      keys); token prompts you to paste one generated at Settings ->
      Developer settings -> Personal access tokens. Run 'pacnix rebuild'
      after any of these -- Nixos/modules/security/github-keys.nix
      (auth/sign) and modules/packages/repos/repos.nix (token) deploy
      them into ~/.ssh / ~/.config/gitctl and wire them up, which needs a
      rebuild (unlike 'dotfiles' above, none of these are read straight
      from /etc/nixos-secrets by anything, so nothing uses them until
      deployed).

  github rem <auth|sign|token>
      Deletes that credential from /etc/nixos-secrets/github. Run 'pacnix
      rebuild' after to also remove the deployed copy and its wiring.
      Remove/revoke the matching public key or token on GitHub yourself
      too -- it keeps working there otherwise.

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
