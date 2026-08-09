# &desc: "Creative server's port-forwarding entries -- the raw MC TCP port plus BlueMap's own web server port."

{ ... }:

{
  # openFirewall (default.nix) only opens serverProperties.server-port
  # (25565) -- BlueMap's own web server (core.conf webserver.port, default
  # 8100) needs its own opening, wired through the same port-forwarding
  # module every self-hosted service uses (see config/system/ports.nix).
  vars.system.ports.entries.bluemap = {
    port = 8100;
    service = "minecraft-server-creative.service";
    mode.local.name = "bluemap";
  };

  # mDNS name only -- the module's resolveUrl port-stripping (bare
  # http://name.local with no port) is an HTTP-only reverse proxy on
  # 80/443 (see modules/system/port-forwarding/lib/router/), which
  # doesn't apply to Minecraft's raw TCP protocol. The MC client still
  # needs the port typed explicitly: creative.local:25565.
  #
  # net.ipv6 = false is required, not optional: the default IPv6 bridge
  # (lib/ipv6-bridge/) defaults to tls.mode = "http/s", an HTTP-aware
  # relay that parses request lines/TLS-sniffs the stream -- it silently
  # corrupted Minecraft's raw binary handshake ("Invalid custom payload
  # payload!" on connect) whenever a client happened to reach it over
  # IPv6. Disabling the bridge leaves ipv4 as a plain firewall ACCEPT
  # with no protocol inspection at all, which is what a raw TCP service
  # like this actually needs.
  vars.system.ports.entries.creative = {
    port = 25565;
    service = "minecraft-server-creative.service";
    mode.local.name = "creative";
    net.ipv6 = false;
  };

  # RCON -- same raw-binary-framing reasoning as the main port above
  # (net.ipv6 = false: the default IPv6 bridge is HTTP-aware and would
  # corrupt RCON's handshake same as it did Minecraft's own). Password
  # lives in server.nix; see its own comment for why it's pinned there
  # instead of a separate secrets file.
  vars.system.ports.entries.creativeRcon = {
    port = 25575;
    service = "minecraft-server-creative.service";
    mode.local.name = "creative-rcon";
    net.ipv6 = false;
  };
}
