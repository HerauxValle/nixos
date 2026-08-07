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
    dnssec = "true";
    domains = [ "~." ];
    settings = {
      Resolve.DNSOverTLS = "yes";
    };
  };

  time.timeZone = config.vars.identity.timeZone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "fr";
  services.xserver.xkb.layout = "fr";
}
