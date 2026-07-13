{ lib }:

# The submodule type behind config.vars.ports.entries.<key> -- mirrors
# modules/system/mountpoints/lib/device-type.nix's own reasoning (a
# submodule, not the loose `attrs` used elsewhere, since fields here
# interact with each other -- e.g. onion/local/public/router are
# mutually exclusive with each other, same as pmg's own CLI flags).

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

    loopbackOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        true -- the service only binds 127.0.0.1, so reaching it from
        outside needs a DNAT rule (networking.nat.forwardPorts)
        alongside the firewall ACCEPT, same as pmg's own runtime
        loopback-bind detection, just declared instead of detected.
        false (default) -- the service already binds 0.0.0.0, a plain
        firewall ACCEPT is enough. Only consulted when ipv4 = true.
      '';
    };

    ipv4 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Firewall ACCEPT for this port (+ DNAT if loopbackOnly). Direct
        equivalent of pmg's own --ipv4 (on by default, same as pmg's
        default_ip = "both").
      '';
    };

    ipv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The IPv6 bridge -- a [::]:port -> 127.0.0.1:port proxy (see
        ../lib/ipv6-bridge/), since NAT/DNAT is an IPv4 concept and
        pmg handles IPv6 reachability this way instead. Direct
        equivalent of pmg's own --ipv6.
      '';
    };

    protocol = lib.mkOption {
      type = lib.types.enum [ "http" "https" "http/s" ];
      default = "http/s";
      description = ''
        Used by the IPv6 bridge's TLS auto-detect (http/s peeks the
        first byte for a TLS ClientHello) and the public tunnel's URL
        scheme. Matches pmg's own default_protocol default.
      '';
    };

    certFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        TLS cert for the IPv6 bridge's "https"/"http/s" modes -- point
        this at your own cert (e.g. via security.acme) instead of the
        shared self-signed one. null (default) -- falls back to the
        auto-generated cert from ../lib/cert/ (`port-forwarding cert
        show/regen/serve` to manage it directly), unless `protocol`
        is "http", in which case no TLS is attempted at all.
      '';
    };

    keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Paired with certFile -- both or neither.";
    };

    onion = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Tor v3 hidden service, via services.tor.relay.onionServices.";
    };

    local = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "mDNS advertisement, via services.avahi.";
    };

    localName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Custom mDNS name (advertised as "<localName>.local"). null
        (default) -- "pmg-<port>.local"-style auto name. Ignored unless
        local = true.
      '';
    };

    public = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "SSH reverse tunnel via config.vars.ports.tunnelHost (see ../lib/public-tunnel.nix).";
    };

    router = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        UPnP port-forward request against the actual home router (see
        ../lib/upnp.nix) -- runtime-only, the router's live state isn't
        known at build time.
      '';
    };

    blocking = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = ''
        Whether a failure on this entry aborts activation instead of
        just warning. null (default) inherits config.vars.ports.blocking;
        set true/false to override per-entry. Same pattern as
        modules/system/mountpoints' own per-entry blocking.
      '';
    };
  };
})
