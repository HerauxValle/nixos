{ }:

# The root CA -- generated once, never rotated (10-year validity,
# "install once, forget"), mirrors pmg's own ensure_ca exactly.

# syntax: python
''
  def ensure_ca():
      if not which("openssl"):
          print("port-forwarding cert: openssl not found", file=sys.stderr)
          sys.exit(1)
      CERT_DIR.mkdir(parents=True, exist_ok=True)
      if CA_FILE.exists() and CA_KEY.exists():
          return CA_FILE, CA_KEY
      subprocess.run(
          [
              "openssl", "req", "-x509", "-newkey", "rsa:4096",
              "-keyout", str(CA_KEY), "-out", str(CA_FILE),
              "-days", "3650",
              "-nodes", "-subj", "/CN=port-forwarding Local CA/O=port-forwarding",
              "-addext", "basicConstraints=critical,CA:TRUE,pathlen:0",
              "-addext", "keyUsage=critical,keyCertSign,cRLSign",
          ],
          check=True, capture_output=True,
      )
      CA_KEY.chmod(0o600)
      print(f"port-forwarding cert: CA generated -- install {CA_FILE} on your devices once", file=sys.stderr)
      return CA_FILE, CA_KEY
''
