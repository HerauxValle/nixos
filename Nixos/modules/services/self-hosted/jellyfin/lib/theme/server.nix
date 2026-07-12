{ pkgs }:

# The CORS-enabled static file server the old theme-server.sh hand-rolled
# with Python's stdlib http.server -- ported near-verbatim, same reason
# it existed originally: Jellyfin's web UI (a different origin/port)
# fetches this cross-origin via CSS @import, so plain `python -m
# http.server` (no CORS headers) doesn't work here. `port`/`directory`
# are passed as argv (see jellyfin.nix's systemd.services entry, driven
# by cfg.themeServer.{bindAddress,port}), not baked in here.

pkgs.writeText "self-hosted-jellyfin-theme-server.py" ''
  import sys
  from http.server import SimpleHTTPRequestHandler, HTTPServer

  bind_address = sys.argv[1]
  port = int(sys.argv[2])
  directory = sys.argv[3]

  class CORSHandler(SimpleHTTPRequestHandler):
      def __init__(self, *args, **kwargs):
          super().__init__(*args, directory=directory, **kwargs)
      def end_headers(self):
          self.send_header("Access-Control-Allow-Origin", "*")
          self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
          self.send_header("Pragma", "no-cache")
          super().end_headers()
      def log_message(self, *args):
          pass

  HTTPServer((bind_address, port), CORSHandler).serve_forever()
''
