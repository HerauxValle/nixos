{ }:

# The leaf cert every ipv6-bridge entry actually serves -- signed by
# the CA above, auto-renews transparently (checked, regenerated if
# expired) since the CA itself never has to be reinstalled on client
# devices for that to keep working. Mirrors pmg's own
# ensure_self_signed_cert, minus the IPv6 SAN entries -- DNS_NAMES is
# computed once in Nix (see ../ preamble.nix) instead of read at
# runtime from state.json plus a live detect_public_ipv6() call.

# syntax: python
''
  def ensure_leaf():
      ca_crt, ca_key = ensure_ca()

      if CERT_FILE.exists() and KEY_FILE.exists():
          expired = subprocess.run(
              ["openssl", "x509", "-in", str(CERT_FILE), "-noout", "-checkend", "0"],
              capture_output=True,
          ).returncode != 0
          if not expired:
              return CERT_FILE, KEY_FILE
          print("port-forwarding cert: leaf cert expired -- regenerating", file=sys.stderr)
          CERT_FILE.unlink(missing_ok=True)
          KEY_FILE.unlink(missing_ok=True)

      CERT_DIR.mkdir(parents=True, exist_ok=True)
      names = list(dict.fromkeys(["port-forwarding"] + DNS_NAMES))
      san = ",".join(f"DNS:{n}" for n in names)

      csr = CERT_DIR / "leaf.csr"
      ext = CERT_DIR / "leaf.ext"
      subprocess.run(
          [
              "openssl", "req", "-newkey", "rsa:2048", "-nodes",
              "-keyout", str(KEY_FILE), "-out", str(csr),
              "-subj", f"/CN={names[0]}",
          ],
          check=True, capture_output=True,
      )
      ext.write_text(
          f"subjectAltName={san}\n"
          "basicConstraints=CA:FALSE\n"
          "keyUsage=critical,digitalSignature,keyEncipherment\n"
          "extendedKeyUsage=serverAuth\n"
      )
      subprocess.run(
          [
              "openssl", "x509", "-req", "-in", str(csr),
              "-CA", str(ca_crt), "-CAkey", str(ca_key), "-CAcreateserial",
              "-out", str(CERT_FILE), "-days", "397",
              "-extfile", str(ext),
          ],
          check=True, capture_output=True,
      )
      csr.unlink(missing_ok=True)
      ext.unlink(missing_ok=True)
      # 0644, not pmg's own 0600 -- the ipv6-bridge services that
      # actually use this key run as DynamicUser (a different
      # unprivileged user each generation), so it has to be readable
      # by someone other than root. This is a low-stakes self-signed
      # LAN convenience cert (avoids a browser warning on your own
      # network), not a real production secret -- pmg's own security
      # model already ran everything as root with no isolation at all,
      # so this is no looser in practice than what it's replacing.
      KEY_FILE.chmod(0o644)
      print(f"port-forwarding cert: leaf cert generated (397 days, SAN: {san})", file=sys.stderr)
      return CERT_FILE, KEY_FILE
''
