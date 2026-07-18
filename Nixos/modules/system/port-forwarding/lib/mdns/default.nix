
{ lib, pkgs }:

# Concatenates every fragment in this directory into one script and
# wires it as a systemd service, one instance per port entry with
# mode.local.enable = true. Same lifecycle/DynamicUser reasoning as
# ../ipv6-bridge/default.nix -- see that file's own top comment.
# Binding :5353 and joining a multicast group are both unprivileged
# socket operations (5353 > 1024), so no AmbientCapabilities needed
# here unlike the bridge.

key: entry:

let
  name = if entry.mode.local.name != null then entry.mode.local.name else "pmg-${toString entry.port}";

  fragments = [
    (import ./preamble.nix { inherit name; })
    (builtins.readFile ./dns-codec.py)
    (builtins.readFile ./responder.py)
  ];

  script = pkgs.writeText "port-forwarding-mdns-${key}.py" (lib.concatStringsSep "\n" fragments);
in

{
  systemd.services."port-forwarding-mdns-${key}" = {
    description = "port-forwarding mDNS responder for ${key} (${name}.local)";
    after = lib.optional (entry.service != null) entry.service;
    bindsTo = lib.optional (entry.service != null) entry.service;
    wantedBy = if entry.service != null then [ entry.service ] else [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${script}";
      Restart = "always";
      RestartSec = 2;
      DynamicUser = true;
    };
  };
}
