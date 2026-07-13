{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.ports option, all commented out. Same
# shape as glossar/main/variables.nix, scoped to one module. Schema:
# modules/system/port-forwarding/default.nix +
# modules/system/port-forwarding/lib/entry-type.nix. Real values on this
# machine: config/system/ports.nix. Full design reference:
# modules/system/port-forwarding/docs/. CLI reference: run
# `port-forwarding help` on this machine.
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
# are -- each is a fully independent mechanism (its own systemd unit
# or activation step, keyed by the entry's own name), so any
# combination can be true on the same entry at once -- confirmed live:
# local + onion + router all active together on one entry, no conflict.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/system/ports.nix and uncomment it there to actually set it.
# =========================================================================

{
  # config.vars.ports = {

  #   # --- globals ------------------------------------------------------------

  #   enabled = true;
  #   # false = the entire module is treated as if it doesn't exist: no
  #   # firewall/DNAT rules, no bridge/mdns/tunnel/cert/router services, no
  #   # activation scripts, not even the `port-forwarding` CLI installed.
  #   # WHY/WHEN: flip off temporarily if you want to rule out this module
  #   # while debugging something unrelated, or before ripping it out
  #   # entirely -- one flag, no need to comment out every entry by hand.

  #   blocking = false;
  #   # Default for entries.<key>.blocking (below) on any entry that
  #   # doesn't set its own. false = a failed UPnP request or unreachable
  #   # public tunnel just warns; true = it aborts `pacnix rebuild` outright.
  #   # WHY/WHEN: leave false unless you have an entry where "silently not
  #   # actually reachable" is worse than "rebuild fails loudly" -- e.g. a
  #   # service you specifically rely on the public tunnel for and would
  #   # rather know immediately if that tunnel breaks.

  #   httpRedirect = false;
  #   # ipv6-bridge entries only: false = plain HTTP is served as-is even
  #   # when a cert exists; true = an HTTP request gets a 301 to the https
  #   # equivalent instead. WHY/WHEN: turn on if you want to force TLS for
  #   # every net.ipv6 = true entry that has a cert, without setting
  #   # tls.mode = "https" (which would reject plaintext outright instead
  #   # of redirecting it) on each one individually.

  #   tunnelHost = "localhost.run";
  #   # SSH host every mode.public entry tunnels to. WHY/WHEN: only reason
  #   # to change this is switching to a different SSH-reverse-tunnel
  #   # provider than localhost.run -- pmg itself never supported one
  #   # either, so this is a real override point pmg never had, not just a
  #   # config knob for its own sake.

  #   resolveUrl = true;
  #   # Master toggle for the port-80/443 .local name resolver. true
  #   # (default) matches pmg's own real default -- a bare
  #   # http://<name>.local reaches a mode.local entry without typing its
  #   # port, which is what actually stripped the port off the end of the
  #   # URL in the old setup. WHY/WHEN: turn off only if you specifically
  #   # want port 80/443 to stay completely free for something else on
  #   # this machine -- every mode.local entry still gets its mDNS name at
  #   # :<port>, this only removes the bare-hostname convenience layer.

  #   redirect = false;
  #   # Only matters while resolveUrl is true. false (default) =
  #   # byte-forwarding -- the resolver proxies raw bytes itself, the
  #   # browser's URL bar never shows the real port. true = an HTTP
  #   # redirect to http://<name>.local:<port>/... instead, letting the
  #   # browser reconnect directly. WHY/WHEN: turn on if you want the URL
  #   # bar to show the real port after the first hop (useful for
  #   # debugging which entry you actually landed on), otherwise leave off.

  #   ipHistory = {
  #     enable = false;
  #     # WHY/WHEN: turn on if this machine's public IP can change (most
  #     # residential connections) and you want a queryable record of when
  #     # it did, e.g. to debug "why did my public tunnel/DDNS stop
  #     # resolving" after the fact. `port-forwarding history changed`
  #     # to check on demand either way, even with this off -- it just
  #     # won't have a timer keeping it current automatically.

  #     interval = "10m";
  #     # systemd.timerConfig.OnUnitActiveSec= for the periodic snapshot.
  #     # WHY/WHEN: shorten if you need to catch a fast-changing IP more
  #     # precisely; lengthen if 10 minutes of imprecision genuinely
  #     # doesn't matter and you'd rather not run the check that often.
  #   };

  #   entries = {

  #     # --- every field, one port ------------------------------------------
  #     jellyfin = {
  #       port = 8096;
  #       # required -- the only field with no default. The port the
  #       # backend actually listens on (verify with `ss -tlnp` or the
  #       # service's own config if unsure -- guessing wrong here means
  #       # everything below silently points at nothing).

  #       enabled = true;
  #       # optional -- false = ignored entirely, as if this entry doesn't
  #       # exist (no firewall/DNAT, no bridge/mdns/tunnel service, no
  #       # router route, no UPnP request). WHY/WHEN: use this instead of
  #       # deleting/commenting out the whole block when you want to
  #       # temporarily stop exposing something but keep every other field
  #       # (service binding, custom cert, mode flags, ...) intact for
  #       # when you flip it back on.

  #       service = "self-hosted-jellyfin.service";
  #       # optional -- lifecycle binds to this systemd unit (BindsTo=/
  #       # After=/wantedBy=): exposure starts and stops with that unit
  #       # natively, confirmed live (stop/start the target, its mdns/
  #       # bridge6 companions follow every single time, not just after a
  #       # rebuild). null (default) = always-on the moment this entry is
  #       # declared, no dependency on any particular unit. WHY/WHEN: set
  #       # this for any entry backed by a real systemd service (which is
  #       # almost always) -- leave null only for something that isn't
  #       # itself a systemd unit (e.g. exposing a port some other machine
  #       # on the LAN owns).

  #       blocking = null;
  #       # optional -- null (omit) inherits the global default above;
  #       # true/false overrides per-entry. See the global `blocking`
  #       # entry above for the why/when -- same reasoning, just scoped to
  #       # this one entry instead of every entry.

  #       # --- net: layer-3/4 reachability -----------------------------------
  #       net = {
  #         ipv4 = true;
  #         # optional -- firewall ACCEPT on IPv4 (+ a DNAT rule too, if
  #         # loopbackOnly below is also true). pmg's own --ipv4, on by
  #         # default. WHY/WHEN: turn off only for an entry you genuinely
  #         # never want reachable over IPv4 at all (e.g. IPv6-only by
  #         # policy, or reached exclusively through mode.onion/
  #         # mode.public instead) -- leaving it off doesn't affect
  #         # net.ipv6/mode.* at all, they're fully independent.

  #         ipv6 = true;
  #         # optional -- the IPv6 bridge, a [::]:port -> 127.0.0.1:port
  #         # proxy (NAT/DNAT is IPv4-only, so IPv6 needs its own path).
  #         # pmg's own --ipv6. Safe to leave true even for a backend that
  #         # already binds a dual-stack socket on its own -- confirmed
  #         # live (Go binaries do this) -- the bridge detects the port's
  #         # already taken at its own bind() and exits cleanly instead of
  #         # conflicting with it. WHY/WHEN: leave on unless you know this
  #         # specific network has no IPv6 at all and would rather not run
  #         # the extra (harmless but unnecessary) bridge process.

  #         loopbackOnly = false;
  #         # optional -- true if the service only binds 127.0.0.1 (needs
  #         # DNAT on top of the firewall ACCEPT to be reachable at all,
  #         # since a plain ACCEPT rule alone can't redirect traffic to a
  #         # loopback-only listener). false (default) means it already
  #         # binds 0.0.0.0, ACCEPT alone is enough. WHY/WHEN: check what
  #         # the backend actually binds (`ss -tlnp`) before guessing --
  #         # getting this wrong either silently does nothing (set false
  #         # when the backend is loopback-only) or adds an unnecessary
  #         # DNAT rule (set true when it wasn't needed).
  #       };

  #       # --- tls: how the IPv6 bridge (and mode.public's URL) handle TLS ---
  #       tls = {
  #         mode = "http/s";
  #         # optional -- "http" (never attempts TLS, a TLS ClientHello
  #         # arriving anyway is dropped as malformed) | "https" (always
  #         # requires TLS, plaintext arriving instead is dropped) |
  #         # "http/s" (default -- peeks the connection's first byte,
  #         # auto-detects, accepts either). Only matters for net.ipv6 or
  #         # mode.public. WHY/WHEN: "http/s" covers almost every case
  #         # (clients that speak either protocol both just work); pick
  #         # "https" only to hard-enforce TLS-only access, or "http" only
  #         # for something you're certain never needs TLS and want to
  #         # skip the auto-detect peek for.

  #         certFile = null;
  #         # optional -- your own cert (e.g. one issued via
  #         # security.acme) instead of the shared self-signed one. null
  #         # (default) falls back to the auto-generated cert from
  #         # ../lib/cert/ (`port-forwarding cert show/regen/serve` to
  #         # manage it directly), unless tls.mode is "http". WHY/WHEN: set
  #         # this only if you have a REAL, browser-trusted cert (e.g. a
  #         # public domain through Let's Encrypt) -- for anything only
  #         # ever reached by *.local names, the shared self-signed one
  #         # (installed once via `port-forwarding cert serve`) is enough
  #         # and needs no per-entry setup.

  #         keyFile = null;
  #         # optional -- paired with tls.certFile, both or neither
  #         # (enforced by an assertion -- setting only one fails the
  #         # rebuild with a clear message instead of silently doing the
  #         # wrong thing).
  #       };

  #       # --- mode: which exposure mechanism(s) are active ------------------
  #       # No longer mutually exclusive -- any combination below can be
  #       # true on the same entry at once, each running independently
  #       # (confirmed live: local + onion + router together, no conflict).
  #       mode = {
  #         onion = false;
  #         # optional -- Tor v3 hidden service, via
  #         # services.tor.relay.onionServices (native NixOS module).
  #         # Reached at http://<address>.onion:<port>/ -- the port still
  #         # has to be typed even though the address itself carries no
  #         # port info (pmg's own onion services work the exact same way:
  #         # VIRTPORT is always set to the real port, never bare 80).
  #         # Three ways to set this field:
  #         #   onion = false;                # off (the default)
  #         #   onion = true;                 # on, persistent address
  #         #   onion = { ephemeral = true; }; # on, fresh address every start
  #         # (same lib.types.coercedTo bool-or-submodule shape as `local`
  #         # below -- a bare true/false is coerced into the
  #         # { enable; ephemeral; } shape either way.)
  #         #
  #         # PERSISTENT (default, ephemeral = false): Tor generates the v3
  #         # keypair once under /var/lib/tor/onion/<key>/ the first time
  #         # this is enabled and reuses it forever after -- confirmed live
  #         # across multiple rebuilds and tor.service restarts, same
  #         # address every time. To force a fresh address by hand anyway:
  #         #   sudo port-forwarding onion regen <key>
  #         # (`port-forwarding help` for the full onion subcommand --
  #         # `onion show [key]` to read the current address(es) back too,
  #         # both need root since /var/lib/tor/onion/ is 0700, owned by
  #         # the tor user, confirmed live. Under the hood this deletes
  #         # only the three keypair files -- hs_ed25519_secret_key,
  #         # hs_ed25519_public_key, hostname -- not the whole directory
  #         # -- its own ownership/mode is set up by services.tor's own
  #         # ExecStartPre, no need to disturb that -- then restarts
  #         # tor.service, which regenerates them fresh.) WHY/WHEN: this
  #         # is what you want almost always -- an address worth
  #         # bookmarking, sharing, or pointing a client at more than once.
  #         #
  #         # EPHEMERAL (ephemeral = true): the exact same three files are
  #         # wiped automatically, every single time tor.service starts, via
  #         # an ExecStartPre this module adds (confirmed live: 4 restarts
  #         # in a row, 4 different addresses, every time) -- the identical
  #         # operation `onion regen` performs by hand, just triggered on
  #         # every start instead of on demand. WHY/WHEN: use only for
  #         # something genuinely meant to be reachable for one session and
  #         # then forgotten -- a one-off file share, a demo you don't want
  #         # linkable again after -- since the address can't be bookmarked
  #         # or shared ahead of time by design. Read the current address
  #         # fresh each time via `sudo port-forwarding onion show <key>`
  #         # (or `journalctl -u tor`) after a (re)start.
  #         #
  #         # Either way: reachable from anywhere without opening a port on
  #         # your actual router or knowing your public IP -- trades the
  #         # address being memorable (unless ephemeral) for reachability
  #         # through Tor with no network-level exposure of this machine's
  #         # real IP at all.

  #         local = false;
  #         # optional -- mDNS advertisement, via ../lib/mdns/ (a from-
  #         # scratch responder, not avahi -- avahi can't publish arbitrary
  #         # custom hostnames, confirmed by reading its source). Three
  #         # ways to set this:
  #         #   local = false;                  # off (the default)
  #         #   local = true;                   # on, auto "pmg-<port>.local" name
  #         #   local = { name = "jellyfin"; };  # on, advertised as "jellyfin.local"
  #         # (replaces the old separate localName field -- a bare
  #         # true/false is coerced into the { enable; name; } shape
  #         # either way via lib.types.coercedTo.) WHY/WHEN: turn on for
  #         # anything reached regularly from other devices on the SAME
  #         # LAN -- this is what lets you type a name instead of
  #         # memorizing an IP, and (combined with the global resolveUrl)
  #         # a bare hostname instead of a port too. Needs
  #         # services.avahi.enable + nssmdns4 on the CLIENT side to
  #         # actually resolve (this module wires that in automatically
  #         # whenever any entry has local set) -- confirmed live this is
  #         # a hard requirement: nss-mdns's own client library doesn't
  #         # speak raw mDNS, it delegates to avahi-daemon's local socket.

  #         public = false;
  #         # optional -- SSH reverse tunnel via tunnelHost above. Needs a
  #         # real SSH key already present for config.vars.username --
  #         # same requirement pmg's own public_open() has; the tunnel
  #         # unit checks for one upfront and fails fast with a clear
  #         # message (`ssh-keygen -t ed25519`) instead of retrying every
  #         # 5 seconds forever if none exists. WHY/WHEN: turn on for
  #         # something you want reachable from anywhere on the real
  #         # internet, quickly, with zero router configuration -- trades
  #         # depending on a third-party relay (localhost.run) for not
  #         # needing UPnP support or port-forwarding rules on your actual
  #         # router at all. The tunnel's public URL is printed by
  #         # localhost.run itself in `journalctl -u port-forwarding-
  #         # tunnel-<key>` on connect, and is NOT persistent -- a new
  #         # random subdomain every time the tunnel reconnects, unlike
  #         # mode.onion's stable address.

  #         router = false;
  #         # optional -- UPnP port-forward request against the actual
  #         # home router (see ../lib/upnp.nix) -- runtime-only, the
  #         # router's live state isn't known at build time, re-attempted
  #         # every activation the same way mountpoints re-mounts every
  #         # activation. WHY/WHEN: turn on for something you want
  #         # reachable from the real internet at your actual public IP
  #         # (not a Tor address or a third-party tunnel subdomain) --
  #         # needs a UPnP-capable/enabled router; if the router rejects
  #         # or doesn't support it (confirmed live: a real, non-blocking
  #         # warning in that case, not a crash), mode.public is the
  #         # fallback pmg itself points you toward in the exact same
  #         # situation.
  #       };
  #     };

  #   };

  # };

  # --- tls.certFile and tls.keyFile must be set together (assertion) ------------
}
