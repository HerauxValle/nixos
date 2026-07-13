{ config, lib, pkgs, ... }:

# Wiring only -- resolves config.vars.ports.entries into real NixOS
# config, one concern per section below. Mapping, from
# ~/Projects/PMG/pmg.py's own features to what actually gets used
# here:
#
#   pmg feature          -> this module
#   ------------------------------------------------------------------
#   LAN firewall ACCEPT  -> networking.firewall.allowedTCPPorts (native)
#   DNAT (loopback-bound) -> networking.nat.forwardPorts (native) +
#                            net.ipv4.conf.all.route_localnet sysctl
#                            (native doesn't set this one, see ./lib/dnat.nix)
#   IPv6 bridge           -> ./lib/ipv6-bridge/ (no native equivalent --
#                            pmg's own HTTP-aware proxy, reimplemented)
#   Tor --onion           -> services.tor.relay.onionServices (native)
#   mDNS --local          -> ./lib/mdns/ (no native equivalent -- avahi
#                            can't publish arbitrary custom hostnames,
#                            only one machine-wide hostname + service-
#                            type discovery records, confirmed by
#                            reading its source; pmg's own responder
#                            reimplemented instead)
#   Public tunnel         -> ./lib/public-tunnel.nix (no native
#                            equivalent -- third-party SSH service)
#   UPnP --router         -> ./lib/upnp.nix, a system.activationScripts
#                            step (the router's live state isn't known
#                            at build time, same category as
#                            modules/system/mountpoints' UUID check)
#   Port-80 name resolver -> ./lib/router/ (no native equivalent)
#   Self-signed certs     -> ./lib/cert/ (no native equivalent; shared
#                            by ./lib/router/ and any ipv6-bridge entry
#                            that wants TLS without its own cert)
#   IP history             -> ./lib/ip-history.nix (no native equivalent)
#   netlink watcher        -> replaced entirely by each entry's own
#                            `service` field binding into systemd's
#                            native BindsTo=/PartOf=/wantedBy=, not
#                            reimplemented (see entry-type.nix)
#
# One flat attrset with static top-level keys (networking/services/
# systemd/system/environment), not a top-level lib.mkMerge [...] list
# built from per-entry mkMerge/mapAttrsToList calls -- confirmed live
# that shape causes infinite recursion: NixOS has to evaluate every
# module's config to determine all contributions to
# config.vars.ports.entries, and a *list* built from
# `mapAttrsToList f entries` can't reveal its own length/contents
# without forcing `entries` first, which is what's being resolved in
# the first place. lib.mkIf/lib.mkMerge are still used per-*value*
# below (e.g. systemd.services), never as a top-level list element
# whose presence depends on entries.

let
  # Per-entry enabled = false is filtered out right here, upstream of
  # every other computation below -- so "ignore it as if it doesn't
  # exist" holds for literally everything derived from `entries`
  # (firewall/DNAT, services, assertions, the lot), not just some of
  # it. The global config.vars.ports.enabled gate wraps the whole
  # returned config further down instead (see the closing let..in).
  entries = lib.filterAttrs (_: e: e.enabled) config.vars.ports.entries;
  globalBlocking = config.vars.ports.blocking;

  ipv4Entries = lib.filterAttrs (_: e: e.ipv4) entries;
  ipv6Entries = lib.filterAttrs (_: e: e.ipv6) entries;
  onionEntries = lib.filterAttrs (_: e: e.onion) entries;
  localEntries = lib.filterAttrs (_: e: e.local) entries;
  publicEntries = lib.filterAttrs (_: e: e.public) entries;
  routerEntries = lib.filterAttrs (_: e: e.router) entries;

  # Same "pmg-<port>" fallback ../lib/mdns/default.nix resolves
  # independently -- duplicated here (one line) rather than threading
  # it through as a shared parameter, so each lib/ piece stays usable
  # on its own.
  resolvedLocalName = e: if e.localName != null then e.localName else "pmg-${toString e.port}";
  localRoutes = lib.mapAttrs' (_: e: lib.nameValuePair "${resolvedLocalName e}.local" e.port) localEntries;
  localDnsNames = lib.mapAttrsToList (_: e: "${resolvedLocalName e}.local") localEntries;

  dnat = import ./lib/dnat.nix { inherit lib; } entries;

  # Only actually wired (see systemd.services/environment.systemPackages
  # below) when something needs it -- resolveUrl's https router, or any
  # ipv6 entry wanting TLS without its own cert.
  needsAutoCert =
    config.vars.ports.resolveUrl
    || lib.any (e: e.ipv6 && e.certFile == null && e.protocol != "http") (lib.attrValues entries);
  cert = import ./lib/cert { inherit lib pkgs; dnsNames = localDnsNames; };

  bridgeService = import ./lib/ipv6-bridge {
    inherit lib pkgs;
    httpRedirect = config.vars.ports.httpRedirect;
    autoCert = cert;
  };
  mdnsService = import ./lib/mdns { inherit lib pkgs; };
  tunnelService = import ./lib/public-tunnel.nix { inherit lib pkgs; };
  tunnelHost = config.vars.ports.tunnelHost;
  upnpStep = import ./lib/upnp.nix { inherit lib pkgs; inherit globalBlocking; };

  routerBuilder = import ./lib/router {
    inherit lib pkgs;
    routes = localRoutes;
    redirectMode = config.vars.ports.redirect;
    certFile = cert.certFile;
    keyFile = cert.keyFile;
    certEnsureService = cert.ensureService;
  };
  # Plain conditional, not lib.mkIf -- mkIf produces an opaque
  # merge-time wrapper (only meaningful as an *option value*, combined
  # across modules), not a plain attrset you can immediately index
  # into. lib/router/default.nix already internally returns {} when
  # localRoutes is empty; this just adds the resolveUrl gate on top.
  router = if config.vars.ports.resolveUrl then routerBuilder else { };

  ipHistoryScriptFile = pkgs.writeText "port-forwarding-ip-history.py" (import ./lib/ip-history.nix { });
in

# Global enable wraps the entire returned config -- same standard
# NixOS `config = lib.mkIf cfg.enable {...};` idiom every service
# module uses, just with no separate options/config split in this file
# (the whole return already stands in for `config`). false here means
# genuinely nothing below is contributed, not even the always-would-
# otherwise-be-installed `port-forwarding` CLI.
lib.mkIf config.vars.ports.enabled {
  # Per-entry checks that genuinely belong at this level, not inside
  # lib/entry-type.nix's own submodule -- `assertions` is a top-level
  # NixOS mechanism (collected into config.assertions and checked
  # during system.build.toplevel assembly), it doesn't auto-propagate
  # up from an arbitrary nested submodule instance the way it would
  # from a real NixOS config -- confirmed live: declaring
  # config.assertions inside the submodule just creates an unrecognized
  # local option there instead ("The option `...assertions' does not
  # exist"), it never reaches here on its own.
  assertions =
    (lib.mapAttrsToList
      (key: e: {
        assertion = (lib.count (x: x) [ e.onion e.local e.public e.router ]) <= 1;
        message = "config.vars.ports.entries.${key}: onion, local, public, and router are mutually exclusive (same as pmg's own CLI flags) -- port ${toString e.port} sets more than one.";
      })
      entries)
    ++ (lib.mapAttrsToList
      (key: e: {
        assertion = (e.certFile == null) == (e.keyFile == null);
        message = "config.vars.ports.entries.${key}: certFile and keyFile must be set together -- port ${toString e.port} sets only one.";
      })
      entries);

  networking.firewall.allowedTCPPorts = lib.mapAttrsToList (_: e: e.port) ipv4Entries;
  networking.nat.enable = lib.mkIf (dnat.forwardPorts != [ ]) true;
  networking.nat.externalInterface =
    lib.mkIf (dnat.forwardPorts != [ ]) config.vars.networkInterface;
  networking.nat.forwardPorts = dnat.forwardPorts;
  boot.kernel.sysctl."net.ipv4.conf.all.route_localnet" = lib.mkIf dnat.needsRouteLocalnet true;

  services.tor.enable = lib.mkIf (onionEntries != { }) true;
  services.tor.relay.onionServices = lib.mapAttrs (_: e: { map = [ e.port ]; }) onionEntries;

  # ./lib/mdns/ only ever ANSWERS mDNS queries on the wire -- it doesn't
  # make this machine (or any client) actually perform an mDNS lookup for
  # a bare `*.local` name in the first place. That's a separate, client-
  # side NSS concern: without an `mdns4_minimal` entry in
  # /etc/nsswitch.conf's hosts line, glibc's getaddrinfo() (which every
  # browser/curl/etc. goes through) never even sends the multicast query,
  # so a *.local name here just fails to resolve regardless of how
  # correct the responder is (confirmed live -- ERR_NAME_NOT_RESOLVED
  # even though tcpdump would show the responder answering correctly).
  # Same system.nssModules/system.nssDatabases.hosts wiring
  # services.avahi.nssmdns4 uses internally (confirmed by reading
  # nixos/modules/services/networking/avahi-daemon.nix directly) --
  # replicated here directly instead of setting services.avahi.enable +
  # nssmdns4, since that would also start avahi-daemon itself publishing
  # its own single machine-wide hostname, a whole extra daemon this
  # module has no use for (./lib/mdns/ already does the actual
  # publishing). mkBefore, not mkAfter -- mdns4_minimal's own
  # "[NOTFOUND=return]" already makes it a no-op for anything that isn't
  # a *.local name, so it's safe to try first; ordering it before `dns`
  # also means a *.local query never even round-trips to a real DNS
  # server first only to (correctly) fail there.
  system.nssModules = lib.mkIf (localEntries != { }) [ pkgs.nssmdns ];
  system.nssDatabases.hosts =
    lib.mkIf (localEntries != { }) (lib.mkBefore [ "mdns4_minimal [NOTFOUND=return]" ]);

  systemd.services = lib.mkMerge (
    (lib.mapAttrsToList (key: e: (mdnsService key e).systemd.services) localEntries)
    ++ (lib.mapAttrsToList (key: e: (bridgeService key e).systemd.services) ipv6Entries)
    ++ (lib.mapAttrsToList (key: e: (tunnelService key e config.vars.username tunnelHost).systemd.services) publicEntries)
    ++ [
      (lib.mkIf needsAutoCert cert.config.systemd.services)
      (router.systemd.services or { })
      (lib.mkIf config.vars.ports.ipHistory.enable {
        port-forwarding-ip-history = {
          description = "port-forwarding IP history snapshot";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.python3}/bin/python3 ${ipHistoryScriptFile} record";
            StateDirectory = "port-forwarding";
            StateDirectoryMode = "0755";
          };
          path = [ pkgs.iproute2 ];
        };
      })
    ]
  );

  systemd.timers.port-forwarding-ip-history = lib.mkIf config.vars.ports.ipHistory.enable {
    description = "port-forwarding IP history snapshot timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = config.vars.ports.ipHistory.interval;
    };
  };

  # One `port-forwarding cert|history ...` command, not two separate
  # binaries -- a thin shell dispatcher onto cert's and ip-history's own
  # already-built scripts (each still a fully independent Python
  # program; this just picks which one runs). Always installed,
  # regardless of needsAutoCert/ipHistory.enable -- both are genuinely
  # useful as manual, on-demand tools even when nothing currently
  # depends on them automatically (e.g. `port-forwarding cert ensure`
  # to pre-generate a cert before declaring an entry that needs one).
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "port-forwarding" ''
      case "''${1:-}" in
        cert)
          shift
          exec ${pkgs.python3}/bin/python3 ${cert.script} "$@"
          ;;
        history)
          shift
          exec ${pkgs.python3}/bin/python3 ${ipHistoryScriptFile} "$@"
          ;;
        *)
          echo "usage: port-forwarding cert [ensure|show|regen|serve [port]]" >&2
          echo "       port-forwarding history [record|changed|ipv4|ipv6 [--last:N]]" >&2
          exit 1
          ;;
      esac
    '')
  ];

  # UPnP -- real bash at activation time, same reasoning as
  # modules/system/mountpoints (the router's state isn't known at
  # eval time). Wrapped in a subshell for the same reason mountpoints'
  # own activation script is -- every module's activationScripts.*.text
  # is concatenated into one shared bash scope. lib.optionalString, not
  # lib.mkIf -- system.activationScripts.<name>.text is types.lines
  # with no default, so mkIf false would drop the definition entirely
  # instead of contributing "" (same trap already documented in
  # modules/services/self-hosted/dotfiles.nix and hit again first-hand
  # fixing modules/services/self-hosted/qbittorrent's own preStart).
  system.activationScripts.port-forwarding-upnp.text = lib.optionalString (routerEntries != { }) ''
    (
      portForwardingFailed=0
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList upnpStep routerEntries)}
      [ "$portForwardingFailed" -eq 0 ]
    ) || exit 1
  '';
}
