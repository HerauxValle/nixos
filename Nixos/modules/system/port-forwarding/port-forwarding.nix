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
#   mDNS --local          -> ./lib/mdns/ publishes (no native equivalent
#                            for THAT part -- avahi can't publish
#                            arbitrary custom hostnames, only one
#                            machine-wide hostname + service-type
#                            discovery records, confirmed by reading its
#                            source; pmg's own responder reimplemented
#                            instead), but services.avahi.enable +
#                            nssmdns4 (both native) are still required
#                            below -- turns out nss-mdns's own client
#                            library doesn't speak raw mDNS at all, it
#                            delegates to avahi-daemon's local socket,
#                            confirmed live via strace (see the comment
#                            just above services.avahi.enable further
#                            down in this file for the full story)
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

  ipv4Entries = lib.filterAttrs (_: e: e.net.ipv4) entries;
  ipv6Entries = lib.filterAttrs (_: e: e.net.ipv6) entries;
  onionEntries = lib.filterAttrs (_: e: e.mode.onion.enable) entries;
  ephemeralOnionKeys = lib.attrNames (lib.filterAttrs (_: e: e.mode.onion.ephemeral) onionEntries);
  localEntries = lib.filterAttrs (_: e: e.mode.local.enable) entries;
  publicEntries = lib.filterAttrs (_: e: e.mode.public) entries;
  routerEntries = lib.filterAttrs (_: e: e.mode.router) entries;

  # Same "pmg-<port>" fallback ../lib/mdns/default.nix resolves
  # independently -- duplicated here (one line) rather than threading
  # it through as a shared parameter, so each lib/ piece stays usable
  # on its own.
  resolvedLocalName = e: if e.mode.local.name != null then e.mode.local.name else "pmg-${toString e.port}";
  localRoutes = lib.mapAttrs' (_: e: lib.nameValuePair "${resolvedLocalName e}.local" e.port) localEntries;
  localDnsNames = lib.mapAttrsToList (_: e: "${resolvedLocalName e}.local") localEntries;

  dnat = import ./lib/dnat.nix { inherit lib; } entries;

  # Only actually wired (see systemd.services/environment.systemPackages
  # below) when something needs it -- resolveUrl's https router, or any
  # ipv6 entry wanting TLS without its own cert.
  needsAutoCert =
    config.vars.ports.resolveUrl
    || lib.any (e: e.net.ipv6 && e.tls.certFile == null && e.tls.mode != "http") (lib.attrValues entries);
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
  # mode.{onion,local,public,router} are no longer mutually exclusive
  # (see entry-type.nix's own header comment for why -- each is a fully
  # independent mechanism, the old pmg-CLI-derived restriction was
  # never a real technical constraint), so the only assertion left here
  # is the one genuine pairing requirement.
  assertions = lib.mapAttrsToList
    (key: e: {
      assertion = (e.tls.certFile == null) == (e.tls.keyFile == null);
      message = "config.vars.ports.entries.${key}: tls.certFile and tls.keyFile must be set together -- port ${toString e.port} sets only one.";
    })
    entries;

  # The router itself (./lib/router/, ports 80/443) never had its own
  # ports opened -- only each entry's OWN port did, above. Real bug,
  # confirmed live: http://<name>.local worked from THIS machine (NixOS's
  # firewall is more permissive for the host talking to itself) but
  # ERR_CONNECTION_REFUSED from every other device on the LAN, while
  # http://<name>.local:<port> (bypassing the router, straight to the
  # entry's own already-open port) worked fine from anywhere. Same
  # resolveUrl/localRoutes condition ./lib/router/default.nix itself uses
  # to decide whether it builds anything at all -- not tied to any one
  # entry/service.
  networking.firewall.allowedTCPPorts = lib.mapAttrsToList (_: e: e.port) ipv4Entries
    ++ lib.optionals (config.vars.ports.resolveUrl && localRoutes != { }) [ 80 443 ];

  # ./lib/mdns/'s own responder binds :5353 and joins 224.0.0.251 just
  # fine on its own (both unprivileged socket operations, see that
  # module's own comment) -- but without this, the firewall drops every
  # inbound query before it ever reaches the socket, from other devices
  # on the LAN AND from this machine's own client-side mDNS lookup alike
  # (confirmed live: nss-mdns's query for searxng.local still failed with
  # this port closed, even though the responder was already up and
  # logging that it was ready to answer). UDP, not TCP -- mDNS is
  # exclusively UDP per RFC 6762.
  networking.firewall.allowedUDPPorts = lib.mkIf (localEntries != { }) [ 5353 ];
  networking.nat.enable = lib.mkIf (dnat.forwardPorts != [ ]) true;
  networking.nat.externalInterface =
    lib.mkIf (dnat.forwardPorts != [ ]) config.vars.networkInterface;
  networking.nat.forwardPorts = dnat.forwardPorts;
  boot.kernel.sysctl."net.ipv4.conf.all.route_localnet" = lib.mkIf dnat.needsRouteLocalnet true;

  services.tor.enable = lib.mkIf (onionEntries != { }) true;
  # VIRTPORT == the real port (same as pmg's own tor_open(): f"HiddenServicePort
  # {port} 127.0.0.1:{port}") -- reaching the service needs that same port
  # typed after the .onion address (http://<addr>.onion:${port}/), same as
  # pmg's own onion services always required. Confirmed genuinely working
  # end-to-end (real Tor client, real rendezvous circuit, HTTP 200) --
  # an earlier "Didn't find rendezvous service ... (DNS lookup pending)"
  # failure during testing turned out to be nothing to do with this
  # config: reading connection_edge.c's handle_hs_exit_conn() directly
  # confirmed that log line fires whenever the VIRTPORT the CLIENT asked
  # for doesn't match any configured HiddenServicePort -- i.e. it was
  # requesting the bare .onion address (implicit port 80, since that's
  # what a URL with no :port defaults to), not this service's actual
  # port. Not a bug here, a testing mistake.
  services.tor.relay.onionServices = lib.mapAttrs (_: e: { map = [ e.port ]; }) onionEntries;

  # ./lib/mdns/ only ever ANSWERS mDNS queries on the wire -- it doesn't
  # make this machine (or any client) actually perform an mDNS lookup for
  # a bare `*.local` name in the first place. That's a separate, client-
  # side NSS concern, and getting it working took three real, independently
  # confirmed fixes (each verified live with strace/tcpdump/a raw mDNS
  # client, not assumed):
  #
  # 1. services.avahi.enable + nssmdns4 -- NOT to publish anything (its own
  #    publish.* stays at its false default; ./lib/mdns/ already does the
  #    real publishing pmg's own mdns_responder.py did). Confirmed via
  #    strace that nss-mdns 0.15.1's libnss_mdns4_minimal.so.2 does NOT
  #    speak raw mDNS itself at all -- it connects(2) to
  #    /var/run/avahi-daemon/socket and asks AVAHI to do the actual
  #    multicast query/cache lookup, failing instantly with ENOENT (zero
  #    network traffic, confirmed with tcpdump) when that socket doesn't
  #    exist. So avahi-daemon running is a hard requirement for *any*
  #    nss-mdns-based resolution, independent of who's answering the wire
  #    query -- the "avahi can't publish arbitrary custom hostnames"
  #    finding elsewhere in this module is still true, but doesn't mean
  #    avahi-daemon itself can be skipped entirely.
  # 2. services.nscd.enableNsncd = false -- system.nssModules (which
  #    nssmdns4 above populates) is only ever exposed as nscd.service's
  #    own LD_LIBRARY_PATH (confirmed by reading
  #    nixos/modules/services/system/nscd.nix directly), so no ordinary
  #    process (a browser's own getaddrinfo(), plain `getent`) can ever
  #    dlopen mdns4_minimal on its own -- only nscd can, and only if it's
  #    real glibc nscd. This repo's own nscd defaults to `enableNsncd =
  #    true` (that option's own default), nixpkgs' Rust reimplementation,
  #    confirmed live to not perform the delegation at all (instant
  #    result, zero network traffic even with a real, working responder
  #    and avahi-daemon both already running).
  # 3. The responder itself (./lib/mdns/responder.nix) has to honor the
  #    "QU" unicast-response bit (RFC 6762 5.4) -- confirmed via a raw
  #    Python mDNS client that avahi-daemon's own outbound query sets QU
  #    and only ever listens on its own ephemeral port for a direct
  #    reply, never joining the multicast group itself for a one-off
  #    resolution. A responder that always multicasts back (this
  #    module's own original behavior) is invisible to it.
  services.avahi.enable = lib.mkIf (localEntries != { }) true;
  services.avahi.nssmdns4 = lib.mkIf (localEntries != { }) true;
  services.nscd.enableNsncd = lib.mkIf (localEntries != { }) false;

  systemd.services = lib.mkMerge (
    (lib.mapAttrsToList (key: e: (mdnsService key e).systemd.services) localEntries)
    ++ (lib.mapAttrsToList (key: e: (bridgeService key e).systemd.services) ipv6Entries)
    ++ (lib.mapAttrsToList (key: e: (tunnelService key e config.vars.username tunnelHost).systemd.services) publicEntries)
    ++ [
      (lib.mkIf needsAutoCert cert.config.systemd.services)
      (router.systemd.services or { })
      # mode.onion.ephemeral -- wipe just the v3 keypair files (not the
      # whole HiddenServiceDir -- that directory's own ownership/mode is
      # set up by services.tor's own ExecStartPre steps, deleting it
      # outright risks racing whichever of the two runs first) before
      # tor.service's real ExecStart, for every entry that asked for a
      # fresh address every start. Tor's own behavior (unchanged, not
      # reimplemented) is to generate a new v3 keypair whenever
      # hs_ed25519_secret_key is missing from an already-existing
      # HiddenServiceDir -- this just guarantees that file is never
      # THERE by the time tor's own binary looks for it, for these
      # specific entries. Confirmed live that
      # systemd.services.tor.serviceConfig.ExecStartPre (a real list,
      # not a single string) merges cleanly with services.tor's own --
      # NixOS concatenates multiple modules' contributions to this
      # exact kind of multi-instance systemd directive automatically,
      # nothing here replaces or races the native module's own prep
      # steps. This has to be inside the SAME top-level systemd.services
      # = lib.mkMerge (...) as everything else in this file, not a
      # separate systemd.services.tor... assignment -- confirmed live,
      # the latter is a genuine Nix "attribute already defined" error
      # against the literal systemd.services key below.
      (lib.mkIf (ephemeralOnionKeys != [ ]) {
        tor.serviceConfig.ExecStartPre = [
          (pkgs.writeShellScript "port-forwarding-onion-wipe-ephemeral" (
            lib.concatMapStringsSep "\n"
              (key: ''
                rm -f ${lib.escapeShellArg "/var/lib/tor/onion/${key}/hs_ed25519_secret_key"} \
                      ${lib.escapeShellArg "/var/lib/tor/onion/${key}/hs_ed25519_public_key"} \
                      ${lib.escapeShellArg "/var/lib/tor/onion/${key}/hostname"}
              '')
              ephemeralOnionKeys
          ))
        ];
      })
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
        help|--help|-h)
          cat <<'EOF'
port-forwarding -- manage the shared self-signed cert and public-IP
history for this machine's declaratively-exposed ports.

USAGE
  port-forwarding <command> [args]

COMMANDS

  cert <subcommand>
    Manage the shared self-signed CA + leaf certificate used by any
    entry with net.ipv6 = true and tls.mode != "http" that doesn't set
    its own tls.certFile/tls.keyFile, and by the port-80/443 .local
    name resolver's own :443 side (resolveUrl = true).

    cert ensure
      Generate the CA + leaf cert if either is missing or the leaf has
      expired/is expiring soon. Idempotent -- safe to run anytime,
      does nothing if everything's already valid. This is exactly what
      the port-forwarding-cert-ensure.service oneshot runs
      automatically whenever something needs it; running it by hand
      just pre-generates a cert before you've even declared an entry
      that needs one.

    cert show
      Print the current leaf cert's subject, expiry date, and SAN
      (subject alternative names -- every *.local name it's currently
      valid for). Says so and does nothing if no cert exists yet.

    cert regen
      Delete the CA and leaf cert/key files and regenerate both from
      scratch. A fresh CA means every device that trusted the old one
      needs to re-trust the new one (see 'cert serve' below) -- every
      bridge/router service using the auto cert picks up the new leaf
      on its own next TLS handshake, no restart needed on this end.

    cert serve [port]
      Temporarily serves the CA certificate (not the leaf -- the CA is
      what a device actually needs to trust, once, to cover every leaf
      this machine ever issues) over plain HTTP for 3 minutes, with
      step-by-step iOS/Safari install instructions, on the given port
      (default 4321). Opens that one port in the firewall for the
      duration via a direct iptables rule (not a config.vars.ports
      entry -- this is a one-off manual action, not a persistent
      exposure), and closes it again when the 3 minutes are up or you
      Ctrl-C. Point an iPhone's Safari at the printed
      http://<lan-ip>:<port>/ URL.

  history <subcommand>
    Query or record this machine's own public IPv4/IPv6 address
    history (up to the last 10 snapshots of each), stored at
    /var/lib/port-forwarding/ip-history.json. Only populated
    automatically if config.vars.ports.ipHistory.enable = true (a
    systemd timer then runs 'history record' on the interval set by
    config.vars.ports.ipHistory.interval, default 10m) -- these
    subcommands work standalone either way, there's just nothing to
    show if the timer's never run.

    history record
      Snapshot the current public IPv4 address (detected via a UDP
      connect to 8.8.8.8:80 -- never actually sends a packet, just
      makes the kernel pick a route/source address -- plus every other
      non-loopback IPv4 address `ip addr` reports) and public IPv6
      addresses (every global-scope, non-private address `ip -6 addr`
      reports), appending to history ONLY if either changed since the
      last recorded snapshot. This is the default if no subcommand is
      given at all.

    history changed
      Same detection as 'record', but prints whether anything actually
      changed since the last snapshot ("still the same", or which of
      ipv4/ipv6 changed and to what).

    history ipv4 [--last:N]
    history ipv6 [--last:N]
      Print up to the last N recorded snapshots for that address
      family, newest first (timestamp + addresses). N defaults to 10
      (the most ever kept); '--last' with no ':N' means 3. Says so and
      does nothing if nothing's been recorded yet.

  help / --help / -h
    This text.

CONFIGURATION
  Every port this machine exposes is declared in
  config/system/ports.nix (config.vars.ports.entries.<key> = { ... };)
  -- port-forwarding itself has no separate config file; everything
  above is either always-on utility (cert/history) or driven entirely
  by what's declared there. See glossar/system/port-forwarding.nix for
  every field with a full explanation of what it does, why, and when
  to use it, or modules/system/port-forwarding/docs/ for the design
  rationale behind each mechanism.

CHECKING STATUS
  Nothing here replaces pmg's own `pmg list`/`pmg status` with a
  single command -- each entry's exposure is a set of ordinary systemd
  units instead, inspect them directly:
    systemctl status port-forwarding-mdns-<key>        # mode.local
    systemctl status port-forwarding-bridge6-<key>     # net.ipv6
    systemctl status port-forwarding-tunnel-<key>      # mode.public
    systemctl status port-forwarding-router{,-https}   # resolveUrl
    journalctl -u tor                                  # mode.onion (native services.tor.relay.onionServices)
  <key> is whatever attribute name you gave the entry in
  config.vars.ports.entries (e.g. "jellyfin"), not the port number.
EOF
          ;;
        *)
          echo "usage: port-forwarding <cert|history|help> ..." >&2
          echo "       run 'port-forwarding help' for full documentation" >&2
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
