{ dnsNames, iptables }:

# First fragment -- imports + constants every other fragment in this
# directory reads. dnsNames (the cert's SAN list) is computed in Nix
# from config.vars.system.ports.entries.*.localName directly (every local =
# true entry's resolved name) -- better than pmg's own _all_local_names,
# which has to read a runtime state.json for the same information we
# already have statically at eval time.

# syntax: python
''
  #!/usr/bin/env python3
  import shutil
  import subprocess
  import sys
  from pathlib import Path

  CERT_DIR = Path("/var/lib/port-forwarding/certs")
  CA_FILE = CERT_DIR / "ca.crt"
  CA_KEY = CERT_DIR / "ca.key"
  CERT_FILE = CERT_DIR / "leaf.crt"
  KEY_FILE = CERT_DIR / "leaf.key"
  DNS_NAMES = ${builtins.toJSON dnsNames}
  IPTABLES = ${builtins.toJSON iptables}


  def which(cmd):
      # shutil.which, not shelling out to the real `which` binary --
      # confirmed live that a systemd unit's minimal PATH doesn't
      # actually have `which` on it at all (FileNotFoundError, not a
      # "command not found" exit code), and Python's stdlib already
      # does the exact same PATH-search logic with no subprocess needed.
      return shutil.which(cmd) is not None
''
