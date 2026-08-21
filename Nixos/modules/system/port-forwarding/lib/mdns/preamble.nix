# &desc: "mDNS preamble -- first Python fragment with imports/constants, the full name table (Nix-interpolated), runtime IP auto-detect (DHCP-robust)."

{ names }:

# First fragment -- imports + the constants every other fragment reads.
# NAMES is the full list this one process answers for (Nix-interpolated,
# same reasoning as ../ipv6-bridge/preamble.nix's PORT/MODE constants --
# see ./default.nix's own top comment for why this is a list now instead
# of one name per process). The IP is auto-detected at runtime instead,
# see responder.py, since it can change after the service starts -- DHCP
# renew, interface roam.

# syntax: python
''
  #!/usr/bin/env python3
  import socket
  import struct
  import sys
  import time

  MCAST_GRP = "224.0.0.251"
  MCAST_PORT = 5353
  TTL = 120
  NAMES = ${builtins.toJSON names}
''
