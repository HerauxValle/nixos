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
# always-on (wantedBy multi-user.target), replacing pmg's own
# netlink-based watcher entirely -- see entry-type.nix's own comment.

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
      # after (Type=simple's default "started" the instant ExecStart's
      # process forks/execs, not once its own internal listener is
      # actually bound) isn't enough ordering on its own -- confirmed
      # live, a real crash: Go's net.Listen("tcp", "0.0.0.0:PORT")
      # binds ONE dual-stack [::]:PORT socket (IPV6_V6ONLY=0, confirmed
      # via strace) that already covers IPv4 too, and if THIS bridge
      # wins the race for that exact [::]:PORT tuple first (its own
      # startup is typically faster than the backend's -- Go's runtime
      # init + FFmpeg detection + an upstream version check all run
      # before its own listener binds), the backend's own bind fails
      # instead, taking the whole real service down. Waiting here for
      # the backend to actually be reachable on 127.0.0.1 guarantees
      # its bind() (dual-stack or not) has already happened -- so it
      # wins any such race deterministically, and this bridge simply
      # doesn't run (Restart=always keeps retrying, harmlessly) on the
      # rare backend that's genuinely dual-stack itself.
      ExecStartPre = pkgs.writeShellScript "port-forwarding-bridge6-${key}-wait-backend" ''
        i=0
        while ! exec 3<>"/dev/tcp/127.0.0.1/${toString entry.port}"; do
          exec 3<&- 3>&- 2>/dev/null
          i=$((i + 1))
          if [ "$i" -ge 20 ]; then
            echo "[bridge6 ${key}] 127.0.0.1:${toString entry.port} never became reachable after 10s -- starting anyway" >&2
            exit 0
          fi
          sleep 0.5
        done
        exec 3<&- 3>&-
      '';
      ExecStart = "${pkgs.python3}/bin/python3 ${script}";
      Restart = "always";
      RestartSec = 2;
      DynamicUser = true;
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
    };
  };
}
