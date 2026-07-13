{ ... }:

# Real values -- schema + the actual mount logic live in
# ../../modules/system/port-forwarding/. Data only, same reasoning as every
# config/<category>/<name>.nix file.
{
  config.vars.ports = {
    enabled = true;

    # Global default -- individual entries.<key>.blocking entries below
    # override this per-port.
    blocking = false;

    httpRedirect = false;

    # true -- matches pmg's own real default (_CONFIG_DEFAULT["resolveurl"]
    # in ~/Projects/PMG/pmg.py is True, not False) -- a bare
    # http://<name>.local reaches a local = true entry without typing its
    # port; this is what stripped the port off the end of the URL in the
    # old setup (the resolver listens on 80/443 itself and proxies to the
    # real port).
    resolveUrl = true;
    redirect = false;
    ipHistory.enable = false;

    # Ported straight from the old pmg setup's real behavior (every
    # service in Scripts/Self-hosted/ got `pmg open <port> --local <name>`
    # as the default, not an optional extra -- see
    # Scripts/Instruct/self-hosted-service/self-hosted-service.md's own
    # "Wiring it up" section). localName set explicitly on every entry
    # below to match pmg's exact old alias -- left null it would fall
    # back to this module's own "pmg-<port>.local" auto name instead,
    # which is NOT the same string. Ports cross-checked against each
    # service's own config/self-hosted/<name>.nix (or, where that file
    # sets `port = null` for "use the upstream default", the real
    # default is noted below). No onion/public/router entries -- nothing
    # in the old setup's docs or scripts recorded a service actually
    # using those.
    entries = {
      jellyfin = {
        port = 8096; # config/self-hosted/jellyfin.nix has port = null -- 8096 is jellyfin's own upstream default
        local = true;
        localName = "jellyfin";
        service = "self-hosted-jellyfin.service";
      };

      searxng = {
        port = 8888; # config/self-hosted/searxng.nix has port = null -- 8888 is server.port in its settings
        localName = "searxng";
        service = "self-hosted-searxng.service";
        public = true;
      };

      ollama = {
        port = 11434; # config/self-hosted/ollama.nix has port = null -- OLLAMA_HOST there is "0.0.0.0:11434"
        local = true;
        localName = "ollama";
        service = "self-hosted-ollama.service";
      };

      stash = {
        port = 9999;
        local = true;
        localName = "stash";
        service = "self-hosted-stash.service";
      };

      openwebui = {
        port = 8080;
        local = true;
        localName = "openwebui";
        service = "self-hosted-openwebui.service";
      };

      odysseus = {
        port = 7000;
        local = true;
        localName = "odysseus";
        service = "self-hosted-odysseus.service";
      };

      qbittorrent = {
        port = 7080; # WebUI\Port from the recovered qBittorrent.conf (see config/self-hosted/qbittorrent.nix)
        local = true;
        localName = "qbittorrent";
        service = "qbittorrent.service"; # native nixpkgs unit name, not self-hosted-qbittorrent
      };

      comfyui = {
        port = 8188; # ComfyUI's own upstream default -- no port override in config/self-hosted/comfyui/comfyui.nix
        local = true;
        localName = "comfyui";
        service = "self-hosted-comfyui.service";
        enabled = false; # matches config.vars.selfHosted.comfyui.autoStart = false right now

        # main.py's own default listen address is 127.0.0.1 -- its
        # execStart (see modules/services/self-hosted/comfyui/comfyui.nix)
        # never passes --listen 0.0.0.0, unlike every other service above.
        # DNAT (via loopbackOnly) is what actually makes the firewall
        # ACCEPT reach anything here.
        loopbackOnly = true;
      };

      # {
      #   uuid-style key -- doesn't have to be meaningful, just how
      #   you'll address it (config.vars.ports.entries.jellyfin).
      # jellyfin = {
      #   port = 8096;
      #   enabled = true;        # optional -- false ignores this entry entirely, as if absent
      #   service = "self-hosted-jellyfin.service"; # optional -- lifecycle bound to this unit
      #   loopbackOnly = false;  # optional -- true if the service only binds 127.0.0.1
      #   ipv4 = true;           # optional -- firewall ACCEPT (+ DNAT if loopbackOnly)
      #   ipv6 = true;           # optional -- the IPv6 bridge
      #   protocol = "http/s";   # optional -- "http" | "https" | "http/s"
      #   certFile = null;       # optional -- TLS cert for https/http-s bridge modes
      #   keyFile = null;        # optional -- paired with certFile
      #   onion = false;         # optional -- Tor v3 hidden service
      #   local = false;         # optional -- mDNS advertisement
      #   localName = null;      # optional -- null = "pmg-<port>"-style auto name
      #   public = false;        # optional -- SSH tunnel via localhost.run
      #   router = false;        # optional -- UPnP port-forward on the router
      #   blocking = false;      # optional -- omit to inherit the global default above
      # };
    };
  };
}
