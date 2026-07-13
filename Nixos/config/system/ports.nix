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
    # http://<name>.local reaches a mode.local entry without typing its
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
    # "Wiring it up" section). mode.local.name set explicitly on every
    # entry below to match pmg's exact old alias -- left null it would
    # fall back to this module's own "pmg-<port>.local" auto name
    # instead, which is NOT the same string. Ports cross-checked against
    # each service's own config/self-hosted/<name>.nix (or, where that
    # file sets `port = null` for "use the upstream default", the real
    # default is noted below). No onion/public/router entries -- nothing
    # in the old setup's docs or scripts recorded a service actually
    # using those.
    entries = {
      jellyfin = {
        port = 8096; # config/self-hosted/jellyfin.nix has port = null -- 8096 is jellyfin's own upstream default
        service = "self-hosted-jellyfin.service";
        mode.local = { name = "jellyfin"; };
      };

      searxng = {
        port = 8888; # config/self-hosted/searxng.nix has port = null -- 8888 is server.port in its settings
        service = "self-hosted-searxng.service";
        mode.local = { name = "searxng"; };
      };

      ollama = {
        port = 11434; # config/self-hosted/ollama.nix has port = null -- OLLAMA_HOST there is "0.0.0.0:11434"
        service = "self-hosted-ollama.service";
        mode.local = { name = "ollama"; };
      };

      stash = {
        port = 9999;
        service = "self-hosted-stash.service";
        mode.local = { name = "stash"; };
      };

      openwebui = {
        port = 8080;
        service = "self-hosted-openwebui.service";
        mode.local = { name = "openwebui"; };
      };

      odysseus = {
        port = 7000;
        service = "self-hosted-odysseus.service";
        mode.local = { name = "odysseus"; };
      };

      qbittorrent = {
        port = 7080; # WebUI\Port from the recovered qBittorrent.conf (see config/self-hosted/qbittorrent.nix)
        service = "qbittorrent.service"; # native nixpkgs unit name, not self-hosted-qbittorrent
        mode.local = { name = "qbittorrent"; };
      };

      comfyui = {
        port = 8188; # ComfyUI's own upstream default -- no port override in config/self-hosted/comfyui/comfyui.nix
        service = "self-hosted-comfyui.service";
        mode.local = { name = "comfyui"; };

        # main.py's own default listen address is 127.0.0.1 -- its
        # execStart (see modules/services/self-hosted/comfyui/comfyui.nix)
        # never passes --listen 0.0.0.0, unlike every other service above.
        # DNAT (via net.loopbackOnly) is what actually makes the firewall
        # ACCEPT reach anything here.
        net.loopbackOnly = true;
      };

      # {
      #   uuid-style key -- doesn't have to be meaningful, just how
      #   you'll address it (config.vars.ports.entries.jellyfin).
      # jellyfin = {
      #   port = 8096;                    # required -- the only field with no default
      #   enabled = true;                 # optional -- false ignores this entry entirely, as if absent
      #   service = "self-hosted-jellyfin.service"; # optional -- lifecycle bound to this unit
      #   blocking = false;               # optional -- omit to inherit the global default above
      #
      #   net = {
      #     ipv4 = true;                  # optional -- firewall ACCEPT (+ DNAT if loopbackOnly)
      #     ipv6 = true;                  # optional -- the IPv6 bridge
      #     loopbackOnly = false;         # optional -- true if the service only binds 127.0.0.1
      #   };
      #
      #   tls = {
      #     mode = "http/s";              # optional -- "http" | "https" | "http/s"
      #     certFile = null;              # optional -- TLS cert for https/http-s bridge modes
      #     keyFile = null;               # optional -- paired with tls.certFile
      #   };
      #
      #   mode = {
      #     onion = false;                # optional -- Tor v3 hidden service
      #     local = false;                # optional -- false | true | { name = "custom"; }
      #                                   #   true            -> mDNS on, auto "pmg-<port>.local" name
      #                                   #   { name = "x"; } -> mDNS on, custom "x.local" name
      #     public = false;               # optional -- SSH tunnel via localhost.run
      #     router = false;               # optional -- UPnP port-forward on the router
      #     # no longer mutually exclusive -- any combination of the four above can be true at once
      #   };
      # };
    };
  };
}
