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
          if e.errno == errno.EADDRINUSE:
              # Real, confirmed case (not hypothetical): some backends'
              # own net.Listen("tcp", "0.0.0.0:PORT") -- Go's stash, at
              # least -- actually binds ONE dual-stack [::]:PORT socket
              # (IPV6_V6ONLY=0) that already covers IPv6 itself, once the
              # ExecStartPre wait-for-backend step (see ./default.nix)
              # guarantees the backend's own bind happens first. Nothing
              # left for this bridge to do in that case -- exit 0 (not
              # the generic sys.exit(1) below) so Restart=on-failure
              # doesn't loop forever retrying a bind that will never
              # succeed.
              print(f"[bridge6 {PORT}] [::]:{PORT} already bound (likely the backend's own dual-stack listener) -- nothing to bridge, exiting.", flush=True)
              sys.exit(0)
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
