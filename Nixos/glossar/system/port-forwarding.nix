{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.ports option, all commented out. Same
# shape as glossar/main/variables.nix, scoped to one module. Schema:
# modules/system/port-forwarding/default.nix +
# modules/system/port-forwarding/lib/entry-type.nix. Real values on this
# machine: config/system/ports.nix. Full design reference:
# modules/system/port-forwarding/docs/.
#
# A declarative reimplementation of ~/Projects/PMG/pmg.py's port-
# exposure mechanisms (LAN firewall/DNAT, IPv6 bridge, Tor onion, mDNS,
# public SSH tunnel, UPnP router forwarding, the port-80 name resolver,
# self-signed certs, IP history), mapped onto real NixOS constructs
# wherever one exists instead of transliterating pmg's own code -- see
# docs/mapping.md for the full pmg-feature -> this-module table.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/system/ports.nix and uncomment it there to actually set it.
# =========================================================================

{
  # config.vars.ports = {

  #   # --- globals ----------------------------------------------------------
  #   enabled = true;          # false = the entire module is treated as if it doesn't exist
  #   blocking = false;       # default for entries.<key>.blocking
  #   httpRedirect = false;   # ipv6-bridge entries: 301 http->https when a cert exists
  #   tunnelHost = "localhost.run"; # SSH host every public = true entry tunnels to
  #   resolveUrl = false;     # master toggle for the port-80/443 .local name resolver
  #   redirect = false;       # resolveUrl byte-forwarding (false) vs 301 redirect (true)

  #   ipHistory = {
  #     enable = false;       # periodic public IPv4/IPv6 snapshot (`port-forwarding history ...`)
  #     interval = "10m";     # systemd.timerConfig.OnUnitActiveSec=
  #   };

  #   entries = {

  #     # --- every field, one port ------------------------------------------
  #     jellyfin = {
  #       port = 8096;                    # required -- the only field with no default
  #       enabled = true;                 # false = ignored entirely, as if this entry doesn't exist

  #       service = "self-hosted-jellyfin.service";
  #       # optional -- lifecycle binds to this systemd unit (BindsTo=/
  #       # After=/wantedBy=) instead of always-on. null (default) = always-on.

  #       loopbackOnly = false; # true = service only binds 127.0.0.1, needs DNAT too
  #       ipv4 = true;          # firewall ACCEPT (+ DNAT if loopbackOnly)
  #       ipv6 = true;          # the IPv6 bridge ([::]:port -> 127.0.0.1:port proxy)
  #       protocol = "http/s";  # "http" | "https" | "http/s" (TLS auto-detect)

  #       certFile = null;      # optional -- your own cert; null falls back to the
  #       keyFile = null;       # shared auto-generated one (unless protocol = "http")

  #       onion = false;        # Tor v3 hidden service
  #       local = false;        # mDNS advertisement
  #       localName = null;     # null = "pmg-<port>.local"-style auto name
  #       public = false;       # SSH reverse tunnel via tunnelHost
  #       router = false;       # UPnP port-forward on the actual home router

  #       blocking = null;      # null (omit) inherits the global default above
  #     };

  #   };

  # };

  # --- onion/local/public/router are mutually exclusive per entry (assertion) ---
  # --- certFile and keyFile must be set together (assertion) --------------------
}
