{ ... }:

# Real values -- schema + the actual mount logic live in
# ../../modules/system/port-forwarding/. Data only, same reasoning as every
# config/<category>/<name>.nix file.
{
  config.vars.ports = {
    enabled = true;

    # Global default -- individual entries.<key>.blocking entries below
    # override this per-port.
    blocking = false;

    httpRedirect = false;
    resolveUrl = false;
    redirect = false;
    ipHistory.enable = false;

    entries = {
      # {
      #   uuid-style key -- doesn't have to be meaningful, just how
      #   you'll address it (config.vars.ports.entries.jellyfin).
      # jellyfin = {
      #   port = 8096;
      #   enabled = true;        # optional -- false ignores this entry entirely, as if absent
      #   service = "self-hosted-jellyfin.service"; # optional -- lifecycle bound to this unit
      #   loopbackOnly = false;  # optional -- true if the service only binds 127.0.0.1
      #   ipv4 = true;           # optional -- firewall ACCEPT (+ DNAT if loopbackOnly)
      #   ipv6 = true;           # optional -- the IPv6 bridge
      #   protocol = "http/s";   # optional -- "http" | "https" | "http/s"
      #   certFile = null;       # optional -- TLS cert for https/http-s bridge modes
      #   keyFile = null;        # optional -- paired with certFile
      #   onion = false;         # optional -- Tor v3 hidden service
      #   local = false;         # optional -- mDNS advertisement
      #   localName = null;      # optional -- null = "pmg-<port>"-style auto name
      #   public = false;        # optional -- SSH tunnel via localhost.run
      #   router = false;        # optional -- UPnP port-forward on the router
      #   blocking = false;      # optional -- omit to inherit the global default above
      # };
    };
  };
}
