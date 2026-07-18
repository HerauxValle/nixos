
{ port, mode, certfile, keyfile, httpRedirect }:

# First fragment concatenated into the final script by ./default.nix --
# imports + the per-port constants every other fragment in this
# directory reads as module-level globals (Nix-interpolated per
# instance, not CLI-parsed like pmg's own _bridge6 args -- each port
# gets its own uniquely generated script, no runtime argument passing
# needed).

# syntax: python
''
  #!/usr/bin/env python3
  import errno
  import os
  import re
  import socket
  import ssl
  import struct
  import sys
  import threading
  import time

  PORT = ${toString port}
  MODE = ${builtins.toJSON mode}
  CERTFILE = ${if certfile == null then "None" else builtins.toJSON certfile}
  KEYFILE = ${if keyfile == null then "None" else builtins.toJSON keyfile}
  HTTP_REDIRECT = ${if httpRedirect then "True" else "False"}
''
