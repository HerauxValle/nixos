{ lib }:

# The submodule type behind config.vars.ports.entries.<key> -- mirrors
# modules/system/mountpoints/lib/device-type.nix's own reasoning (a
# submodule, not the loose `attrs` this repo otherwise uses, since
# fields here interact with each other).
#
# Grouped into net/tls/mode below -- still plain option-tree nesting,
# not separate submodule *types* (NixOS's module system treats
# `options.net.ipv4 = lib.mkOption {...};` identically to
# `options = { net = { ipv4 = lib.mkOption {...}; }; };`, no submodule
# boundary needed just to nest) -- so config/system/ports.nix reads by
# CONCERN (network-layer reachability, TLS, which exposure mechanism)
# instead of one flat list of same-looking booleans. port/enabled/
# service/blocking stay flat: each is a fact about the entry as a
# whole, not about any one of net/tls/mode specifically.
#
# onion/local/public/router used to be mutually exclusive, mirroring
# pmg's own CLI (`pmg open <port> [--onion|--public|--local]` only ever
# accepts one flag per invocation). That was a CLI-argument-parsing
# constraint, not a real one -- each mechanism is fully independent
# (its own systemd unit or activation-script step, keyed by this
# entry's own name, touching no shared state), confirmed by reading
# every one of ./mdns/, ./cert/, ../public-tunnel.nix, ../upnp.nix, and
# services.tor.relay.onionServices directly. So the mutual-exclusivity
# assertion is gone (was in ../port-forwarding.nix, removed there too)
# -- any combination of the four can be true on the same entry.

lib.types.submodule ({ config, ... }: {
  options = {
    port = lib.mkOption {
      type = lib.types.port;
      description = "The port to expose. The only required field.";
    };

    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        false -- this entry is treated as if it doesn't exist at all
        (no firewall/DNAT, no bridge/mdns/tunnel service, no router
        route, no UPnP request), without having to actually remove the
        entry to disable it. Same field/semantics as
        config.vars.mountpoints.device.<key>.enabled.
      '';
    };

    service = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        A systemd unit name (e.g. "self-hosted-jellyfin.service") this
        entry's exposure binds its lifecycle to (BindsTo=/PartOf=) --
        exposure starts and stops with that unit natively, instead of
        pmg's own netlink-based watcher polling for the listener to
        come up. null (default) -- always-on the moment this entry is
        declared, no dependency on any particular unit.
      '';
    };

    blocking = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = ''
        Whether a failure on this entry (a UPnP request the router
        rejects, a public tunnel that can't reach tunnelHost, ...)
        aborts activation instead of just printing a warning. null
        (default) inherits config.vars.ports.blocking; set true/false
        to override per-entry. Deliberately stays one flat field
        instead of one per net/tls/mode entry below -- it's a
        blast-radius decision about THIS ENTRY's activation-time
        failures in general (whichever mechanism produces one), not a
        fact specific to any single mechanism. Same pattern as
        modules/system/mountpoints' own per-entry blocking.
      '';
    };

    # --- net: layer-3/4 reachability ------------------------------------
    net = {
      ipv4 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Firewall ACCEPT for this port on IPv4 (+ a DNAT rule too, if
          net.loopbackOnly is also true). Direct equivalent of pmg's
          own --ipv4 (on by default, same as pmg's default_ip =
          "both").
        '';
      };

      ipv6 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          The IPv6 bridge -- a [::]:port -> 127.0.0.1:port proxy (see
          ../lib/ipv6-bridge/), since NAT/DNAT is an IPv4-only concept
          and pmg handles IPv6 reachability this way instead. Direct
          equivalent of pmg's own --ipv6. Safe to leave true even for a
          backend that already binds a dual-stack socket on its own
          (confirmed real for some Go binaries, e.g. via strace) -- the
          bridge detects the port's already taken at its own bind()
          and exits cleanly instead of conflicting with it (see
          ../lib/ipv6-bridge/server.nix's own comment for the full
          story, including the real crash this used to cause before
          that was fixed).
        '';
      };

      loopbackOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          true -- the service only binds 127.0.0.1, so reaching it
          from outside needs a DNAT rule (networking.nat.forwardPorts)
          alongside the firewall ACCEPT, same as pmg's own runtime
          loopback-bind detection, just declared instead of detected.
          false (default) -- the service already binds 0.0.0.0, a
          plain firewall ACCEPT is enough on its own. Only consulted
          when net.ipv4 is also true.
        '';
      };
    };

    # --- tls: how the IPv6 bridge (and the public tunnel's URL scheme)
    # handle TLS -----------------------------------------------------
    tls = {
      mode = lib.mkOption {
        type = lib.types.enum [ "http" "https" "http/s" ];
        default = "http/s";
        description = ''
          Used by the IPv6 bridge's TLS auto-detect (http/s peeks the
          connection's first byte for a TLS ClientHello) and the
          public tunnel's URL scheme. "http" never attempts TLS (a
          ClientHello arriving anyway is treated as a malformed HTTP
          request and dropped); "https" always requires it (plaintext
          arriving instead is dropped, since it isn't valid TLS);
          "http/s" (default, matches pmg's own default_protocol)
          auto-detects per connection, accepting either. Only actually
          consulted for entries using the IPv6 bridge (net.ipv6 =
          true) or the public tunnel (mode.public = true) -- has no
          effect otherwise.
        '';
      };

      certFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          TLS cert for the IPv6 bridge's "https"/"http/s" modes --
          point this at your own cert (e.g. one issued via
          security.acme) instead of the shared self-signed one. null
          (default) -- falls back to the auto-generated cert from
          ../lib/cert/ (`port-forwarding cert show/regen/serve` to
          manage it directly), unless tls.mode is "http", in which
          case no TLS is attempted at all and this is ignored.
        '';
      };

      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Paired with tls.certFile -- both or neither (enforced by an assertion in ../port-forwarding.nix).";
      };
    };

    # --- mode: which exposure mechanism(s) this entry uses -------------
    # No longer mutually exclusive (see this file's own header comment)
    # -- any combination of the four below can be true on the same
    # entry at once, each running independently.
    mode = {
      onion = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Tor v3 hidden service, via services.tor.relay.onionServices.
          Reached at http://<address>.onion:<port>/ -- the port has to
          be typed even though the .onion address itself carries no
          port information; pmg's own onion services work the exact
          same way (VIRTPORT is always set to the real port, never 80).
        '';
      };

      local = lib.mkOption {
        type = lib.types.coercedTo lib.types.bool
          (enable: { inherit enable; name = null; })
          (lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = ''
                  Always true when this submodule form (mode.local = {
                  ...  }) is used at all -- set mode.local = false
                  (the plain bool, not { enable = false; }) to
                  actually disable mDNS for this entry.
                '';
              };
              name = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Custom mDNS name (advertised as "<name>.local"). null
                  (default) -- falls back to a "pmg-<port>.local"-style
                  auto name instead.
                '';
              };
            };
          });
        default = { enable = false; name = null; };
        description = ''
          mDNS advertisement, via ../lib/mdns/. Three ways to set this
          field:
            mode.local = false;                  # off (the default)
            mode.local = true;                    # on, auto "pmg-<port>.local" name
            mode.local = { name = "jellyfin"; };  # on, advertised as "jellyfin.local"
          A bare true/false is coerced into the { enable; name; } shape
          shown above (via lib.types.coercedTo) -- reading
          config.vars.ports.entries.<key>.mode.local elsewhere in this
          module always sees that same attrset shape either way, never
          a raw bool.
        '';
      };

      public = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          SSH reverse tunnel via config.vars.ports.tunnelHost (see
          ../lib/public-tunnel.nix). Needs a real SSH key already
          present for config.vars.username -- same requirement pmg's
          own public_open() has; the tunnel unit checks for one
          upfront and fails fast with an actionable message instead of
          retrying forever if none exists (see that file's own
          comment).
        '';
      };

      router = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          UPnP port-forward request against the actual home router
          (see ../lib/upnp.nix) -- runtime-only, the router's live
          state isn't known at build time.
        '';
      };
    };
  };
})
