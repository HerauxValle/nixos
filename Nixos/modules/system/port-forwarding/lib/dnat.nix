{ lib }:

# DNAT for loopback-bound services -- entries with ipv4 = true and
# loopbackOnly = true need networking.nat.forwardPorts (external
# interface -> 127.0.0.1:port) on top of the plain firewall ACCEPT,
# same as pmg's own runtime loopback-bind detection, just declared
# instead of detected. route_localnet isn't set by the nat module
# itself (confirmed by reading its source -- it only sets the
# *.forwarding sysctls), so that's surfaced here too for
# port-forwarding.nix to wire in only when actually needed.

entries:

let
  loopbackEntries = lib.filterAttrs (_: e: e.ipv4 && e.loopbackOnly) entries;
in
{
  forwardPorts = lib.mapAttrsToList
    (_: e: {
      sourcePort = e.port;
      destination = "127.0.0.1:${toString e.port}";
      proto = "tcp";
    })
    loopbackEntries;

  needsRouteLocalnet = loopbackEntries != { };
}
