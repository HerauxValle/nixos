{ name }:

# First fragment -- imports + the per-entry constant every other
# fragment reads (the name is Nix-interpolated per instance, same
# reasoning as ../ipv6-bridge/preamble.nix's PORT/MODE constants; the
# IP is auto-detected at runtime instead, see responder.py, since it
# can change after the service starts -- DHCP renew, interface roam).

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
  NAME = ${builtins.toJSON name}
''
