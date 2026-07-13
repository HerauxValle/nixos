{ lib, pkgs, routes, redirectMode, certFile, keyFile, certEnsureService }:

# Concatenates every fragment in this directory into one script and
# wires two systemd services -- port-forwarding-router (plain :80) and
# port-forwarding-router-https (TLS :443, depends on ../cert/'s ensure
# service) -- both starting together whenever resolveUrl is enabled,
# same as pmg's own router_start()/router_https_start() always being
# called as a pair. Returns {} (no services) when routes is empty --
# nothing to route, matches pmg's own "port 80 stays free" behavior
# when resolveurl is off.

if routes == { } then
  { }
else
  let
    script = pkgs.writeText "port-forwarding-router.py" (
      lib.concatStringsSep "\n" [
        (import ./preamble.nix { inherit routes redirectMode; })
        (builtins.readFile ./handler.py)
        (builtins.readFile ./server.py)
      ]
    );
  in
  {
    systemd.services.port-forwarding-router = {
      description = "port-forwarding .local name resolver (:80)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${script}";
        Restart = "always";
        RestartSec = 2;
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      };
    };

    systemd.services.port-forwarding-router-https = {
      description = "port-forwarding .local name resolver (:443, TLS)";
      after = [ certEnsureService ];
      bindsTo = [ certEnsureService ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${script} --https --cert ${certFile} --key ${keyFile}";
        Restart = "always";
        RestartSec = 2;
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      };
    };
  }
