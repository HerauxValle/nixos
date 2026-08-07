# &desc: "Port-forwarding mDNS concatenator -- one consolidated systemd service answering every local=true entry's .local name, UDP 5353 multicast, no elevated caps needed."

{ lib, pkgs }:

# Concatenates every fragment in this directory into one script and wires
# it as ONE systemd service answering for every declared .local name --
# not one process per entry, like this used to be. Originally one
# instance per port.mode.local.enable entry, each independently binding
# :5353 with SO_REUSEPORT; found the hard way that Linux's SO_REUSEPORT
# delivers each incoming multicast datagram to exactly ONE socket in the
# reuse group (kernel hash), not to every listener in it -- so with N
# per-entry responders plus avahi-daemon all competing for the same
# port, any given query only had a 1-in-N-ish chance of ever reaching
# the one process that actually knew the answer. Confirmed live: `getent
# hosts <name>.local` succeeded 1 time out of 5 attempts with just 3
# competitors running (avahi-daemon + 2 responders). One process, one
# name table, zero self-competition for the socket -- same fix shape as
# ../router/'s own single static ROUTES table, just for DNS instead of
# HTTP.
#
# Trade-off, deliberate: the old per-entry service could
# `bindsTo`/`after` its one backend's own systemd unit, so a name
# stopped being advertised the moment its backend did. One consolidated
# responder can't do that per-name without a live "is this backend up
# right now" check on every single query -- real added complexity for a
# soft nicety, not the reliability bug this rewrite exists to fix.
# Every name is advertised unconditionally instead; a backend that's
# down still resolves fine, then fails at the HTTP layer exactly how
# ../router/'s own "backend not reachable" 502 already handles it.
names:

if names == [ ] then
  { }
else
  let
    script = pkgs.writeText "port-forwarding-mdns.py" (
      lib.concatStringsSep "\n" [
        (import ./preamble.nix { inherit names; })
        (builtins.readFile ./dns-codec.py)
        (builtins.readFile ./responder.py)
      ]
    );
  in
  {
    systemd.services.port-forwarding-mdns = {
      description = "port-forwarding mDNS responder (${lib.concatStringsSep ", " names})";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${script}";
        Restart = "always";
        RestartSec = 2;
        DynamicUser = true;
      };
    };
  }
