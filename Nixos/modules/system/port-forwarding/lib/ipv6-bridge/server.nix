{ }:

# Bind [::]:PORT (IPv6-only socket -- IPv4 clients reach the port
# directly via networking.firewall/nat instead, see ../dnat.nix) and
# accept in a loop, one daemon thread per connection via
# handle_connection. Last fragment concatenated by ./default.nix, so
# it's the one that actually runs.

# syntax: python
''
  TLS_CTX = make_tls_context()

  def main():
      srv = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
      srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
      srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
      try:
          srv.bind(("::", PORT))
      except OSError as e:
          print(f"[bridge6 {PORT}] could not bind [::]:{PORT}: {e}", file=sys.stderr, flush=True)
          sys.exit(1)
      srv.listen(128)
      print(f"[bridge6 {PORT}] {MODE} [::]:{PORT} -> 127.0.0.1:{PORT}", flush=True)

      while True:
          try:
              conn, addr = srv.accept()
          except OSError:
              break
          threading.Thread(target=handle_connection, args=(conn,), daemon=True).start()

  if __name__ == "__main__":
      main()
''
