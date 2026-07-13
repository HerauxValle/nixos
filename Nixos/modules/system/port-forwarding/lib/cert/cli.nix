{ }:

# argv dispatch -- mirrors pmg's own `pmg cert show|regen|serve`
# subcommands, plus `ensure` (used internally by the systemd oneshot
# any auto-cert bridge entry depends on, not meant to be typed by
# hand). Last fragment concatenated by ../default.nix, so it's the one
# that runs.

# syntax: python
''
  def cmd_show():
      if not CERT_FILE.exists():
          print("no leaf cert yet -- run 'port-forwarding cert ensure' or 'regen' first")
          return
      r = subprocess.run(
          ["openssl", "x509", "-in", str(CERT_FILE), "-noout", "-subject", "-enddate", "-ext", "subjectAltName"],
          capture_output=True, text=True,
      )
      print((r.stdout or r.stderr).strip())


  def cmd_regen():
      for f in (CA_FILE, CA_KEY, CERT_FILE, KEY_FILE):
          f.unlink(missing_ok=True)
      ensure_leaf()


  def main():
      args = sys.argv[1:]
      cmd = args[0] if args else "ensure"
      if cmd == "ensure":
          ensure_leaf()
      elif cmd == "show":
          cmd_show()
      elif cmd == "regen":
          cmd_regen()
      elif cmd == "serve":
          port = int(args[1]) if len(args) > 1 else 4321
          cert_serve(port)
      else:
          print("usage: port-forwarding cert [ensure|show|regen|serve [port]]", file=sys.stderr)
          sys.exit(1)


  if __name__ == "__main__":
      main()
''
