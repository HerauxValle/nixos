# &desc: "Deploys the personal GitHub auth/sign SSH keys (secrets github add auth/sign) from root-owned /etc/nixos-secrets into ~/.ssh with correct user ownership, retracting them the same way once removed. Wires ~/.ssh/config (auth) and global git signing config (sign) at fixed paths, regardless of whether a key currently exists at them."

{ config, ... }:

let
  homeDir = config.vars.identity.homeDirectory;
  username = config.vars.identity.username;
  secretsDir = "/etc/nixos-secrets/github";

  # Key material presence is inherently a runtime fact (root-owned files
  # under /etc, generated on demand by `secrets github add/rem`) -- it
  # can't reliably be seen at eval time (nixos-rebuild switch runs without
  # --impure; see modules/backup/dotfiles/lib/activation/preflight.sh for
  # the same caveat). So this only ever copies-if-source-exists /
  # removes-if-not, every rebuild -- `secrets github rem` deleting the
  # source is exactly what makes the next rebuild retract the deployed
  # copy, no separate "undo" step needed.
  deployKeyScript =
    kind: destName:
    let
      src = "${secretsDir}/${kind}";
      dest = "${homeDir}/.ssh/${destName}";
    in
    ''
      if [ -f "${src}" ]; then
        install -d -m 700 -o ${username} -g users "${homeDir}/.ssh"
        install -m 600 -o ${username} -g users "${src}" "${dest}"
        install -m 644 -o ${username} -g users "${src}.pub" "${dest}.pub"
      else
        rm -f "${dest}" "${dest}.pub"
      fi
    '';
in
{
  system.activationScripts.deployGithubKeys.text =
    deployKeyScript "auth" "github-auth" + deployKeyScript "sign" "github-sign";

  home-manager.users.${username} = {
    # Declared unconditionally at fixed paths -- harmless before the auth
    # key exists (ssh just has nothing to offer for github.com yet), and
    # picks it up the moment `secrets github add auth` + a rebuild deploys
    # it. Nix-managed like everything else here: a manually hand-edited
    # ~/.ssh/config would get overwritten on the next rebuild -- add more
    # Host blocks here, not by hand.
    home.file.".ssh/config".text = ''
      Host github.com
        IdentityFile ~/.ssh/github-auth
        IdentitiesOnly yes
    '';

    # Same reasoning for the sign key -- gpg.format/user.signingKey are
    # inert until something actually tries to sign a commit, so declaring
    # them before the key exists doesn't break anything. Points at the
    # PUBLIC half specifically (not the private key) -- confirmed working
    # without any ssh-agent involved, matching GitHub's own documented
    # convention: ssh-keygen -Y sign finds the adjacent private key by
    # naming convention either way. commit.gpgsign is deliberately left
    # unset -- opt into auto-signing yourself (globally, or per-repo via
    # vars.packages.repos.*.gpgSign) rather than this silently turning it
    # on everywhere the moment a sign key happens to exist.
    home.file.".config/git/config".text = ''
      [gpg]
        format = ssh
      [user]
        signingKey = ~/.ssh/github-sign.pub
    '';
  };
}
