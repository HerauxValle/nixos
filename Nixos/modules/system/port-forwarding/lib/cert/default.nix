{ lib, pkgs, dnsNames }:

# Concatenates every fragment in this directory into one script, wires
# a systemd oneshot (port-forwarding-cert-ensure.service) that any
# ipv6-bridge entry with certFile/keyFile left null can depend on
# (bindsTo/after) to get a working auto-generated cert instead of just
# falling back to plain HTTP. The CLI itself isn't wired here -- script
# is exposed so ../../port-forwarding.nix can fold it into one unified
# `port-forwarding cert|history ...` command instead of a separate
# per-feature binary. Real state (CA + leaf cert/key) lives under
# /var/lib/port-forwarding/certs -- StateDirectory, not a Nix-managed
# value, since the private keys involved must never touch the Nix
# store.

let
  fragments = [
    (import ./preamble.nix { inherit dnsNames; })
    (import ./ca.nix { })
    (import ./leaf.nix { })
    (import ./serve.nix { iptables = "${pkgs.iptables}/bin/iptables"; })
    (import ./cli.nix { })
  ];

  script = pkgs.writeText "port-forwarding-cert.py" (lib.concatStringsSep "\n" fragments);
in
{
  # Resolved paths + the unit name any bridge entry needing an
  # auto-generated cert depends on -- read by ../ipv6-bridge/default.nix.
  certFile = "/var/lib/port-forwarding/certs/leaf.crt";
  keyFile = "/var/lib/port-forwarding/certs/leaf.key";
  ensureService = "port-forwarding-cert-ensure.service";
  inherit script;

  config = {
    systemd.services.port-forwarding-cert-ensure = {
      description = "port-forwarding self-signed cert (generate/renew if needed)";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.python3}/bin/python3 ${script} ensure";
        StateDirectory = "port-forwarding/certs";
        # 0755, not the tighter 0750 -- the ipv6-bridge services that
        # read leaf.crt/leaf.key run as an arbitrary DynamicUser each
        # generation, not a group this directory could sensibly be
        # scoped to, so they need to at least traverse in. ca.key
        # itself stays 0600 (see ca.nix) -- only the leaf cert/key
        # inside are meant to be broadly readable.
        StateDirectoryMode = "0755";
      };
      path = [ pkgs.openssl ];
    };
  };
}
