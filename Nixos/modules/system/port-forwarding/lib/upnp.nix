# &desc: "Port-forwarding UPnP builder -- runtime activation-time bash, detects local IP (UDP to 8.8.8.8), calls upnpc per entry, lease self-healing on every activation."

{ lib, pkgs, globalBlocking }:

# UPnP port-forward request against the actual home router -- can't be
# a build-time Nix declaration (the router's live state isn't known at
# eval time, same category as modules/system/mountpoints' own UUID-
# presence check), so this is real bash in system.activationScripts,
# re-applied every activation (a router's own UPnP lease isn't
# necessarily permanent, same reasoning as mountpoints re-mounting
# every activation). Reimplements pmg's own upnp_open: detect the local
# IP via a UDP connect to 8.8.8.8:80 (never actually sends a packet,
# just makes the kernel pick a route/source address), then
# `upnpc -a <local-ip> <port> <port> TCP <key>`.

key: entry:

let
  blocking = if (entry.blocking or null) != null then entry.blocking else globalBlocking;
  upnpc = "${pkgs.miniupnpc}/bin/upnpc";
  python3 = "${pkgs.python3}/bin/python3";

  warn = msg:
    if blocking then
      ''
        printf '\033[0;31merror: modules/system/port-forwarding: entry.${key}: ${msg}\033[0m\n' >&2
        portForwardingFailed=1
      ''
    else
      ''printf '\033[0;33mwarning: modules/system/port-forwarding: entry.${key}: ${msg}\033[0m\n' >&2'';
in

''
  local_ip="$(${python3} -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("8.8.8.8", 80)); print(s.getsockname()[0])' 2>/dev/null)"
  if [ -z "$local_ip" ]; then
    ${warn "could not detect local IP address -- UPnP mapping skipped."}
  else
    if ! ${upnpc} -a "$local_ip" ${toString entry.port} ${toString entry.port} TCP ${lib.escapeShellArg key} >/dev/null 2>&1; then
      ${warn "UPnP mapping for port ${toString entry.port} failed -- router may not support/allow it (try the public tunnel instead)."}
    fi
  fi
''
