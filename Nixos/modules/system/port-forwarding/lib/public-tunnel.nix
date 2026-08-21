
# &desc: "Generates a supervised systemd service to manage an SSH reverse tunnel via a specified public provider with localized key validation."

{ lib, pkgs }:

# SSH reverse tunnel via config.vars.system.ports.tunnelHost (default
# "localhost.run", matching pmg's own hardcoded choice -- it doesn't
# support an alternate provider either -- but a real override point
# instead of a literal in this file now) -- pmg's own public_open,
# minus the manual reconnect-loop/timeout/state.json bookkeeping:
# systemd's Restart=always supervises the process, and the URL the
# tunnel host prints on connect just lands in the journal
# (`journalctl -u port-forwarding-tunnel-<key>`) instead of a separate
# state file to query. Runs as config.vars.identity.username (not root, no
# sudo -u dance) -- ssh as root ignores $HOME for ~/.ssh/id_* (a
# deliberate OpenSSH hardening behavior), and localhost.run rejects the
# username "root" outright regardless of key, same two reasons pmg's
# own comment gives for why it has to drop privileges at all; running
# this service as the real user from the start sidesteps both. The
# "localhost" in -R 80:localhost:<port> is the *remote* side's own
# loopback (standard SSH remote-forward syntax), not tunnelHost --
# left alone deliberately, it isn't the same fact.

key: entry: username: tunnelHost:

{
  systemd.services."port-forwarding-tunnel-${key}" = {
    description = "port-forwarding public tunnel for ${key} (port ${toString entry.port}, via ${tunnelHost})";
    after = lib.optional (entry.service != null) entry.service;
    bindsTo = lib.optional (entry.service != null) entry.service;
    wantedBy = if entry.service != null then [ entry.service ] else [ "multi-user.target" ];
    # 60/3 -- SSH's own "Permission denied (publickey)" (no key present at
    # all, or the key isn't accepted) can't ever be fixed by retrying --
    # it's the exact same failure every 5s, forever, under the previous
    # unconditional Restart=always. Confirmed live: this is a REAL, easy
    # way to end up here (a fresh account with no ~/.ssh key yet at all).
    # 3 tries in 60s is enough to ride out a genuinely transient network
    # blip on localhost.run's end, then stop and surface the problem
    # instead of burying a permanent misconfiguration under endless
    # identical journal spam.
    startLimitIntervalSec = 60;
    startLimitBurst = 3;
    serviceConfig = {
      User = username;
      # pmg's own public_open() has the same silent problem in a
      # different shape -- a 20s wait for a URL that will never come,
      # then one clear die() with an actionable message. This is the
      # same idea moved to ExecStartPre, checked once up front instead
      # of after a timeout: if ssh has no key to even attempt with,
      # every one of the default identity file names is checked
      # directly (this is what ssh itself tries with no -i given) --
      # missing all of them means the actual ssh attempt below is
      # certain to fail the identical way, so fail fast with a message
      # that says what to actually do about it.
      ExecStartPre = pkgs.writeShellScript "port-forwarding-tunnel-${key}-check-key" ''
        for f in id_ed25519 id_ed25519_sk id_ecdsa id_ecdsa_sk id_rsa id_dsa; do
          if [ -f "/home/${username}/.ssh/$f" ]; then
            exit 0
          fi
        done
        echo "[port-forwarding tunnel ${key}] no SSH private key found in /home/${username}/.ssh/ -- public = true needs one (matches pmg's own public_open() requirement): ssh-keygen -t ed25519" >&2
        exit 1
      '';
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.openssh}/bin/ssh"
        "-o" "StrictHostKeyChecking=no"
        "-o" "ServerAliveInterval=30"
        "-o" "BatchMode=yes"
        "-R" "80:localhost:${toString entry.port}"
        "${username}@${tunnelHost}"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
