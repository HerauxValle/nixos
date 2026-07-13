{ dnsNames }:

# First fragment -- imports + constants every other fragment in this
# directory reads. dnsNames (the cert's SAN list) is computed in Nix
# from config.vars.ports.entries.*.localName directly (every local =
# true entry's resolved name) -- better than pmg's own _all_local_names,
# which has to read a runtime state.json for the same information we
# already have statically at eval time.

# syntax: python
''
  #!/usr/bin/env python3
  import subprocess
  import sys
  from pathlib import Path

  CERT_DIR = Path("/var/lib/port-forwarding/certs")
  CA_FILE = CERT_DIR / "ca.crt"
  CA_KEY = CERT_DIR / "ca.key"
  CERT_FILE = CERT_DIR / "leaf.crt"
  KEY_FILE = CERT_DIR / "leaf.key"
  DNS_NAMES = ${builtins.toJSON dnsNames}


  def which(cmd):
      return subprocess.run(["which", cmd], capture_output=True).returncode == 0
''
