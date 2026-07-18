# &desc: "Router preamble -- first Python fragment with imports/ROUTES dict (local entries, Nix-computed), one script for both :80/:443 (argv flag selects mode)."

{ routes, redirectMode }:

# First fragment -- imports + the two constants every other fragment
# reads. ROUTES (hostname -> port) is computed once in Nix from every
# local = true entry's resolved name, unlike pmg's own
# _router_lookup_port, which re-reads a live state.json on every single
# request -- we already have this statically at eval time. One script
# serves both :80 (plain) and :443 (TLS, cert from ../cert/) --
# unlike pmg's own cmd_route/cmd_route_https (two near-duplicate
# functions), the https-or-not choice is just an argv flag here (see
# server.py), so the lookup/relay/handler logic isn't duplicated.

# syntax: python
''
  #!/usr/bin/env python3
  import socket
  import ssl
  import sys
  import threading

  ROUTES = ${builtins.toJSON routes}
  REDIRECT_MODE = ${if redirectMode then "True" else "False"}
''
