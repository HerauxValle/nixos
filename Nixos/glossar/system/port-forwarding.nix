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
# Each entry below is grouped by CONCERN, not one flat list of 15
# same-looking fields: port/enabled/service/blocking stay flat (facts
# about the entry as a whole), net.* is layer-3/4 reachability, tls.*
# is how the IPv6 bridge handles TLS, mode.* is which exposure
# mechanism(s) are active. See entry-type.nix's own header comment for
# the full reasoning, including why onion/local/public/router used to
# be mutually exclusive (mirroring pmg's own CLI flags) and no longer
# are -- each is a fully independent mechanism, any combination can be
# true on the same entry at once.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/system/ports.nix and uncomment it there to actually set it.
# =========================================================================

{
  # config.vars.ports = {

  #   # --- globals ------------------------------------------------------------
  #   enabled = true;          # false = the entire module is treated as if it doesn't exist
  #   blocking = false;       # default for entries.<key>.blocking
  #   httpRedirect = false;   # ipv6-bridge entries: 301 http->https when a cert exists
  #   tunnelHost = "localhost.run"; # SSH host every mode.public entry tunnels to
  #   resolveUrl = true;      # master toggle for the port-80/443 .local name resolver --
  #                           # true (default) matches pmg's own real default: a bare
  #                           # http://<name>.local reaches a mode.local entry without
  #                           # typing its port.
  #   redirect = false;       # resolveUrl byte-forwarding (false) vs 301 redirect (true)

  #   ipHistory = {
  #     enable = false;       # periodic public IPv4/IPv6 snapshot (`port-forwarding history ...`)
  #     interval = "10m";     # systemd.timerConfig.OnUnitActiveSec=
  #   };

  #   entries = {

  #     # --- every field, one port ------------------------------------------
  #     jellyfin = {
  #       port = 8096;                    # required -- the only field with no default

  #       enabled = true;
  #       # optional -- false = ignored entirely, as if this entry doesn't exist
  #       # (no firewall/DNAT, no bridge/mdns/tunnel service, no router route,
  #       # no UPnP request), without having to actually remove the entry.

  #       service = "self-hosted-jellyfin.service";
  #       # optional -- lifecycle binds to this systemd unit (BindsTo=/After=/
  #       # wantedBy=): exposure starts and stops with that unit natively.
  #       # null (default) = always-on the moment this entry is declared.

  #       blocking = null;
  #       # optional -- null (omit) inherits the global default above; true/false
  #       # overrides whether a failure on THIS entry (a rejected UPnP request,
  #       # an unreachable public tunnel, ...) aborts activation or just warns.
  #       # One flat field, not one per net/tls/mode below -- it's a blast-
  #       # radius choice about this entry's failures in general.

  #       # --- net: layer-3/4 reachability -----------------------------------
  #       net = {
  #         ipv4 = true;
  #         # optional -- firewall ACCEPT on IPv4 (+ a DNAT rule too, if
  #         # loopbackOnly below is also true). pmg's own --ipv4, on by default.

  #         ipv6 = true;
  #         # optional -- the IPv6 bridge, a [::]:port -> 127.0.0.1:port proxy
  #         # (NAT/DNAT is IPv4-only, so IPv6 needs its own path). pmg's own
  #         # --ipv6. Safe to leave true even for a backend that already binds
  #         # a dual-stack socket on its own -- the bridge detects the port's
  #         # already taken and exits cleanly instead of conflicting with it.

  #         loopbackOnly = false;
  #         # optional -- true if the service only binds 127.0.0.1 (needs DNAT
  #         # on top of the firewall ACCEPT to be reachable at all). false
  #         # (default) means it already binds 0.0.0.0, ACCEPT alone is enough.
  #       };

  #       # --- tls: how the IPv6 bridge (and mode.public's URL) handle TLS ---
  #       tls = {
  #         mode = "http/s";
  #         # optional -- "http" (never attempts TLS) | "https" (always
  #         # requires it) | "http/s" (default -- peeks the first byte, auto-
  #         # detects per connection). Only matters for net.ipv6 or mode.public.

  #         certFile = null;
  #         # optional -- your own cert (e.g. via security.acme) instead of the
  #         # shared self-signed one. null (default) falls back to the
  #         # auto-generated cert from ../lib/cert/, unless tls.mode is "http".

  #         keyFile = null;
  #         # optional -- paired with tls.certFile, both or neither (assertion).
  #       };

  #       # --- mode: which exposure mechanism(s) are active ------------------
  #       # No longer mutually exclusive -- any combination below can be true
  #       # on the same entry at once, each running independently.
  #       mode = {
  #         onion = false;
  #         # optional -- Tor v3 hidden service, via
  #         # services.tor.relay.onionServices. Reached at
  #         # http://<address>.onion:<port>/ -- the port still has to be typed
  #         # (pmg's own onion services work the same way: VIRTPORT is always
  #         # the real port, never bare 80).

  #         local = false;
  #         # optional -- mDNS advertisement. Three ways to set this:
  #         #   local = false;                  # off (the default)
  #         #   local = true;                   # on, auto "pmg-<port>.local" name
  #         #   local = { name = "jellyfin"; };  # on, advertised as "jellyfin.local"
  #         # (replaces the old separate localName field -- a bare true/false
  #         # is coerced into the { enable; name; } shape either way.)

  #         public = false;
  #         # optional -- SSH reverse tunnel via tunnelHost above. Needs a real
  #         # SSH key already present for config.vars.username -- same
  #         # requirement pmg's own public_open() has; the tunnel unit checks
  #         # upfront and fails fast with an actionable message if none exists,
  #         # instead of retrying forever.

  #         router = false;
  #         # optional -- UPnP port-forward request against the actual home
  #         # router -- runtime-only, the router's live state isn't known at
  #         # build time.
  #       };
  #     };

  #   };

  # };

  # --- tls.certFile and tls.keyFile must be set together (assertion) ------------
}
