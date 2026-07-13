{ lib, pkgs }:

# SSH reverse tunnel via config.vars.ports.tunnelHost (default
# "localhost.run", matching pmg's own hardcoded choice -- it doesn't
# support an alternate provider either -- but a real override point
# instead of a literal in this file now) -- pmg's own public_open,
# minus the manual reconnect-loop/timeout/state.json bookkeeping:
# systemd's Restart=always supervises the process, and the URL the
# tunnel host prints on connect just lands in the journal
# (`journalctl -u port-forwarding-tunnel-<key>`) instead of a separate
# state file to query. Runs as config.vars.username (not root, no
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
    serviceConfig = {
      User = username;
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.openssh}/bin/ssh"
        "-o" "StrictHostKeyChecking=no"
        "-o" "ServerAliveInterval=30"
        "-o" "BatchMode=yes"
        "-R" "80:localhost:${toString entry.port}"
        "${username}@${tunnelHost}"
      ];
      Restart = "always";
      RestartSec = 5;
    };
  };
}
