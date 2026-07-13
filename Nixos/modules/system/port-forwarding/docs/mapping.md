# pmg -> port-forwarding, feature by feature

`~/Projects/PMG/pmg.py` is an imperative CLI (`pmg open <port> [--onion|
--local|--public|--router]`) that mutates live firewall/DNS/process
state on demand, with a `state.json` tracking what it did so `list`/
`status` survive a reboot. `port-forwarding` is the same feature set
made declarative: you describe the end state in
`config/system/ports.nix`, `pacnix rebuild` makes it real, and there is
no separate state file -- the declared config *is* the state.

Every mechanism below was read directly from pmg's own source before
being ported, not guessed from its `--help` text or docstrings alone.

| pmg feature | port-forwarding | why |
|---|---|---|
| LAN firewall ACCEPT | `networking.firewall.allowedTCPPorts` | Native NixOS option, nothing to reimplement. |
| DNAT (loopback-bound service) | `networking.nat.forwardPorts` + `net.ipv4.conf.all.route_localnet` sysctl | Native option covers the DNAT itself; `route_localnet` isn't set by that module (confirmed by reading its source), so `lib/dnat.nix` adds only that one sysctl. |
| IPv6 bridge (`--ipv6`, `bridge6`) | `lib/ipv6-bridge/` | No native equivalent -- this is a real HTTP-aware reverse proxy (header rewriting, cookie/redirect fixup for the scheme change, WebSocket/SSE passthrough), reimplemented as concatenated Nix-generated Python, not a thin wrapper around `socat`/nginx. |
| Tor (`--onion`) | `services.tor.relay.onionServices` | Native, mature module. Confirmed live that `relay.onionServices` does **not** require `relay.enable` (that flag is about becoming a public Tor relay/exit node, a much bigger decision) -- verified by reading the module's own warning text and finding no assertion tying the two together. `mode.onion.ephemeral` and `port-forwarding onion regen <key>` go beyond what pmg's own onion services ever offered -- pmg's `HiddenServicePort` was always persistent-only, no equivalent of "fresh address every start" existed. |
| mDNS (`--local`) | `lib/mdns/` | Avahi cannot publish arbitrary custom hostnames -- confirmed by reading `avahi-daemon.nix`'s source: it has one machine-wide `hostName` plus `extraServiceFiles` for service-*discovery* records (Bonjour/`dns-sd` browsing), neither of which lets `pmg-8096.local` resolve directly in a browser's URL bar the way pmg's own hand-rolled responder does. Reimplemented instead, byte-for-byte protocol-compatible with pmg's own `mdns_responder.py`. |
| Public tunnel (`--public`) | `lib/public-tunnel.nix` | No native equivalent (third-party SSH service). Simpler than pmg's own version -- systemd's `Restart=always` replaces the manual reconnect/timeout loop, and the URL the tunnel host prints on connect just lands in the journal instead of a separate state file to query. |
| UPnP (`--router`) | `lib/upnp.nix`, a `system.activationScripts` step | Can't be a build-time declaration at all -- the router's live state isn't known at eval time, same category as `modules/system/mountpoints`' own UUID-presence check. Re-applied every activation, non-blocking by default (see `decisions.md`). |
| Port-80/443 name resolver (`resolveurl`/`redirect`) | `lib/router/` | No native equivalent. Unlike pmg's own two near-duplicate functions (`cmd_route`/`cmd_route_https`), this is one script with the https-or-not choice as an argv flag, since the lookup/relay/handler logic doesn't actually differ. |
| Self-signed certs (`cert show/regen/serve`) | `lib/cert/` | No native equivalent. SAN list is computed once in Nix from every `local = true` entry's resolved name -- pmg's own version re-reads a live `state.json` for the same information on every cert regen, which we already have statically at eval time. |
| IP history (`show changed`/`show ipv4\|ipv6 --last`) | `lib/ip-history.nix` | No native equivalent. A systemd timer replaces pmg's on-demand-only recording (a machine that's never manually asked "did my IP change" never gets a snapshot in pmg's own version). |
| netlink watcher (reactive open/close as a service's listener comes up/down) | Each entry's own `service` field, systemd `BindsTo=`/`After=`/`wantedBy=` | Not reimplemented at all -- systemd already does this natively and better. See `architecture.md`'s "lifecycle binding" section for exactly how the wiring works. |
| `pmg list`/`status` | `systemctl status port-forwarding-*` / `journalctl -u port-forwarding-*` / `port-forwarding onion show [key]` | The declared config already tells you what *should* exist; systemd tells you what actually does. `onion show` is the one exception worth a real subcommand -- the address itself lives in a `0700` file only root can read, not in any systemd unit's own status output. |
| `pmg install`/`uninstall` | N/A | Superseded entirely by Nix's own packaging -- there's no symlink step to manage. |
