{ }:

# Raw bidirectional byte relay -- once the header rewrite phase (see
# http-request.nix/http-response.nix) has sent the (possibly rewritten)
# headers, everything after that (request body, response body,
# WebSocket frames, SSE events) is just opaque bytes copied straight
# through, same as pmg's own _router_pipe.

# syntax: python
''
  def relay(src, dst):
      try:
          while True:
              chunk = src.recv(65536)
              if not chunk:
                  break
              dst.sendall(chunk)
      except OSError:
          pass
      finally:
          try:
              dst.shutdown(socket.SHUT_WR)
          except OSError:
              pass
''
