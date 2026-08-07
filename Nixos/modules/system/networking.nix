# &desc: "Network config -- hostname, NetworkManager, pinned MAC address (commented out), DNS-over-TLS, timezone, en_US locale, French keyboard layout."

{ config, ... }:

{
  networking = {
    hostName = config.vars.identity.hostName;
    networkmanager.enable = false;

    # Pinned deliberately, not the hardware default -- see local notes for why.
    # Currently disabled -- not in use.
        # interfaces.${config.vars.identity.networkInterface}.macAddress = null;

    interfaces.enp3s0.mtu = 1492;

    nameservers = [
      "1.1.1.1#cloudflare-dns.com"
      "9.9.9.9#dns.quad9.net"
    ];
  };

  services.resolved = {
    enable = false;
    settings = {
      Resolve = {
        DNSSEC = "true";
        Domains = [ "~." ];
        DNSOverTLS = "yes";
        # resolved's own built-in mDNS is a second, independent
        # implementation from avahi-daemon + modules/system/port-forwarding's
        # own custom responder -- left at its default (per-link "resolve",
        # effectively on) it binds :5353 as a THIRD competitor alongside
        # those two, and it's specifically the one nscd's "resolve" NSS
        # step (nsswitch.conf's hosts line) queries via resolved's varlink
        # socket. Confirmed live via strace: with mdns4_minimal not
        # actually reaching avahi's socket, "resolve" is what nscd falls
        # through to, and resolved's own internal mDNS resolution for a
        # port-forwarding-published *.local name hung indefinitely rather
        # than answering -- same root cause class as the SO_REUSEPORT
        # multicast-delivery bug fixed in ../services/self-hosted's
        # sibling module, just a third listener instead of two. This
        # system's *.local resolution is deliberately owned end-to-end by
        # avahi (services.avahi.nssmdns4) + the custom responder already;
        # resolved doing its own thing on top was never wanted, just never
        # turned off.
        MulticastDNS = "no";
      };
    };
  };

  time.timeZone = config.vars.identity.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fr";
  services.xserver.xkb.layout = "fr";
}
