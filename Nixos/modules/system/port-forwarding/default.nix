{ lib, ... }:

# Schema only -- a declarative reimplementation of ~/Projects/PMG/pmg.py's
# port-exposure mechanisms (LAN firewall/DNAT, IPv6 bridge, Tor onion,
# mDNS, public SSH tunnel, UPnP router forwarding), mapped onto real
# NixOS constructs wherever one exists (services.tor, services.avahi,
# networking.nat.forwardPorts) instead of transliterating pmg's own
# code -- see modules/system/port-forwarding/port-forwarding.nix's own top
# comment for the full mapping. pmg's netlink-based watcher (reactive
# open/close as the underlying service's listener comes up/down) is
# replaced entirely by each entry's own `service` field binding into
# systemd's native BindsTo=/PartOf=, not reimplemented.
#
# Every pmg feature is now ported: the port-80 "resolveurl"/"redirect"
# name-resolver lives in ./lib/router/, self-signed cert management
# (pmg's own `cert show/regen/serve`) in ./lib/cert/, and IP history
# tracking (pmg's own `show changed`/`show ipv4|ipv6 --last`) in
# ./lib/ip-history.py.
#
# Entry submodule type lives in ./lib/entry-type.nix (split out, same
# reasoning as mountpoints' own device-type.nix). Logic that resolves
# entries into real firewall rules/services lives in ./port-forwarding.nix
# and ./lib/*.nix, imported below.
{
  imports = [ ./port-forwarding.nix ];

  options.vars.ports = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        false -- this entire module is treated as if it doesn't exist:
        no firewall/DNAT rules, no bridge/mdns/tunnel/cert/router
        services, no activation scripts, not even the `port-forwarding`
        CLI installed. Same field/semantics as
        config.vars.mountpoints.enabled (both added together, for
        consistency between the two sibling modules).
      '';
    };

    blocking = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Global default for whether a failed entry (e.g. the public
        tunnel can't reach localhost.run) blocks activation. Per-entry
        entries.<key>.blocking overrides this. Same pattern as
        config.vars.mountpoints.blocking.
      '';
    };

    httpRedirect = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Global -- applies to every ipv6 = true entry's bridge. false
        (default, matches pmg's own http_redirect default): plain HTTP
        requests are served as-is. true: an HTTP request on an entry
        that also has a cert (certFile/keyFile set) gets a 301 to the
        https:// equivalent instead of being served over plain HTTP.
      '';
    };

    tunnelHost = lib.mkOption {
      type = lib.types.str;
      default = "localhost.run";
      description = ''
        SSH host every public = true entry tunnels to. Was a hardcoded
        literal in lib/public-tunnel.nix -- pmg itself doesn't support
        an alternate provider either, so the default matches its
        behavior exactly, but this is now a real override point instead
        of a hardcoded string.
      '';
    };

    resolveUrl = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Master toggle for the port-80/443 .local name resolver (see
        ./lib/router/) -- true (default, matches pmg's own
        _CONFIG_DEFAULT["resolveurl"], which really is True there, not
        False) means a bare http://<name>.local reaches any local = true
        entry without typing its port: the resolver listens on 80/443
        itself and proxies to the real port behind the scenes, same as
        pmg's own `pmg _route`. This is what let the port get dropped off
        the end of the URL in the old setup -- without this, every
        local = true entry only ever resolves at http://<name>.local:<port>,
        never bare. false -- port 80 stays free, exactly as if this
        feature didn't exist.
      '';
    };

    redirect = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Only matters while resolveUrl is true. false (default, matches
        pmg's own default): byte-forwarding -- the resolver proxies the
        raw bytes itself, the browser never sees the real port. true:
        an HTTP redirect to http://<name>.local:<port>/... instead,
        letting the browser reconnect directly (URL bar shows the real
        port).
      '';
    };

    ipHistory = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Periodically snapshot this machine's own public IPv4/IPv6
          addresses to /var/lib/port-forwarding/ip-history.json (see
          ./lib/ip-history.py), queryable via `port-forwarding history
          ...` -- same idea as pmg's own `show changed`/
          `show ipv4|ipv6 --last`.
        '';
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "10m";
        description = "systemd.timerConfig.OnUnitActiveSec= for the periodic snapshot.";
      };
    };

    entries = lib.mkOption {
      type = lib.types.attrsOf (import ./lib/entry-type.nix { inherit lib; });
      default = { };
      description = ''
        Exposed ports, keyed by whatever string you want to address
        them by (e.g. config.vars.ports.entries.jellyfin) -- the key
        doesn't have to be meaningful. See ./lib/entry-type.nix for the
        field list.
      '';
    };
  };
}
