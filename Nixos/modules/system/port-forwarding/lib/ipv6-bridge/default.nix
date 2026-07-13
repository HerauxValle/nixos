{ lib, pkgs, httpRedirect, autoCert }:

# Concatenates every fragment in this directory into one script and
# wires it as a systemd service, one instance per port entry with
# ipv6 = true. Fragment order doesn't matter for correctness (Python
# resolves function calls at call time, not definition time) -- kept
# roughly bottom-up (helpers first, server.nix's main() last) for
# readability, not because it has to be.
#
# autoCert (from ../cert/) is the fallback for any entry that wants
# https/http-s but leaves certFile/keyFile null -- same shared
# self-signed cert the port-80/443 router uses, matching pmg's own
# ensure_self_signed_cert being a singleton every TLS consumer shares,
# not a per-entry generation.
#
# Lifecycle: wantedBy = [ entry.service ] registers this unit as
# *wanted by* the target service (a real Wants= dependency injected
# into that unit without touching its own definition -- how NixOS's
# wantedBy is designed to work), bindsTo + after make it start after
# and stop with that service (plus the cert-ensure service too, when
# falling back to autoCert). entry.service = null falls back to
# always-on (wantedBy multi-user.target). This replaces the OPEN/CLOSE
# half of pmg's own netlink-based watcher entirely -- see
# entry-type.nix's own comment -- but not the READINESS half: Wants=/
# After= only orders unit *start jobs* (Type=simple's "started" fires
# the instant the process forks, not once it's actually bound its own
# port), so ./wait-backend.nix reintroduces pmg's exact same
# process-connector-netlink technique for that one narrower purpose --
# see its own header comment for the real crash this fixes and why a
# sleep/poll loop isn't good enough.

key: entry:

let
  usingAutoCert = entry.certFile == null && entry.protocol != "http";
  certfile = if entry.certFile != null then entry.certFile else if usingAutoCert then autoCert.certFile else null;
  keyfile = if entry.keyFile != null then entry.keyFile else if usingAutoCert then autoCert.keyFile else null;

  fragments = [
    (import ./preamble.nix {
      inherit (entry) port;
      mode = entry.protocol;
      inherit certfile keyfile httpRedirect;
    })
    (import ./wait-backend.nix { })
    (import ./tls.nix { })
    (import ./relay.nix { })
    (import ./http-request.nix { })
    (import ./http-response.nix { })
    (import ./handler.nix { })
    (import ./server.nix { })
  ];

  script = pkgs.writeText "port-forwarding-bridge6-${key}.py" (lib.concatStringsSep "\n" fragments);

  extraDeps = lib.optional (entry.service != null) entry.service
    ++ lib.optional usingAutoCert autoCert.ensureService;
in

{
  systemd.services."port-forwarding-bridge6-${key}" = {
    description = "port-forwarding IPv6 bridge for ${key} (port ${toString entry.port})";
    after = extraDeps;
    bindsTo = lib.optional (entry.service != null) entry.service;
    wantedBy = if entry.service != null then [ entry.service ] else [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${script}";
      # on-failure, not always -- a clean exit 0 (see ./server.nix) means
      # "the backend turned out to already be dual-stack, nothing to
      # bridge", a terminal state that shouldn't keep restarting every
      # 2s forever. Any real crash (nonzero exit) still retries.
      Restart = "on-failure";
      RestartSec = 2;
      DynamicUser = true;
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
    };
  };
}
