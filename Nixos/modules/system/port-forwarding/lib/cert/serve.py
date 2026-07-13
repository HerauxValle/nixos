import subprocess
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import CA_FILE, IPTABLES, ensure_ca


def _detect_usable_ips():
    # Same trick as lib/ip-history.py's own detect_usable_ips --
    # duplicated, not shared, since this is a genuinely separate
    # assembled script.
    import ipaddress
    import socket as _socket

    ips = []
    try:
        with _socket.socket(_socket.AF_INET, _socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            primary = s.getsockname()[0]
        if primary and not ipaddress.ip_address(primary).is_loopback:
            ips.append(primary)
    except Exception:
        pass
    return ips


def cert_serve(port=4321):
    import http.server
    import threading
    import time
    import urllib.parse

    ensure_ca()
    cert_data = CA_FILE.read_bytes()

    html = ("""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>port-forwarding -- install cert</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0 }
  body { font-family: -apple-system, sans-serif; background: #0f1117; color: #e8eaf0;
         display: flex; justify-content: center; padding: 2rem 1rem }
  .card { max-width: 480px; width: 100%; background: #1a1d27; border-radius: 16px;
           padding: 2rem; box-shadow: 0 4px 32px #0008 }
  h1 { font-size: 1.4rem; margin-bottom: .4rem; color: #fff }
  .sub { color: #888; font-size: .9rem; margin-bottom: 1.8rem }
  ol { padding-left: 1.4rem; line-height: 2 }
  li { color: #ccc; font-size: .95rem }
  li b { color: #e8eaf0 }
  .btn { display: block; margin: 2rem auto 0; padding: .9rem 2rem;
          background: #5C8FA5; color: #fff; border: none; border-radius: 12px;
          font-size: 1.05rem; font-weight: 600; text-decoration: none;
          text-align: center; cursor: pointer }
  .note { margin-top: 1.2rem; font-size: .8rem; color: #555; text-align: center }
  .timer { margin-top: .6rem; font-size: .8rem; color: #c04; text-align: center }
</style>
</head>
<body>
<div class="card">
  <h1>Install port-forwarding certificate</h1>
  <p class="sub">Needed once so Safari trusts HTTPS from this machine</p>
  <ol>
    <li>Tap <b>Download Certificate</b> below</li>
    <li>Safari shows <em>"This website is trying to download a configuration profile"</em> -&gt; tap <b>Allow</b></li>
    <li>Go to <b>Settings</b> (home screen)</li>
    <li>Tap the <b>Profile Downloaded</b> banner at the top -&gt; <b>Install</b></li>
    <li>Navigate to <b>Settings -&gt; General -&gt; About -&gt; Certificate Trust Settings</b></li>
    <li>Toggle <b>port-forwarding</b> to <b>on</b> -&gt; <b>Continue</b></li>
  </ol>
  <a class="btn" href="/port-forwarding-ca.crt">Download CA Certificate</a>
  <p class="note">This page auto-closes in 3 minutes.</p>
  <p class="timer" id="t"></p>
</div>
<script>
var end = Date.now() + 3*60*1000;
function tick() {
  var s = Math.max(0, Math.round((end - Date.now()) / 1000));
  document.getElementById('t').textContent = s + 's remaining';
  if (s > 0) setTimeout(tick, 1000);
}
tick();
</script>
</body>
</html>""").encode()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *a):
            pass

        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path
            if path == "/port-forwarding-ca.crt":
                self.send_response(200)
                self.send_header("Content-Type", "application/x-x509-ca-cert")
                self.send_header("Content-Disposition", 'attachment; filename="port-forwarding-ca.crt"')
                self.send_header("Content-Length", str(len(cert_data)))
                self.end_headers()
                self.wfile.write(cert_data)
            else:
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(html)))
                self.end_headers()
                self.wfile.write(html)

    class DualStackServer(http.server.HTTPServer):
        address_family = socket.AF_INET6

        def server_bind(self):
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            super().server_bind()

    import socket
    srv = DualStackServer(("::", port), Handler)

    def shutdown():
        time.sleep(180)
        srv.shutdown()

    threading.Thread(target=shutdown, daemon=True).start()

    subprocess.run([IPTABLES, "-I", "INPUT", "-p", "tcp", "--dport", str(port), "-j", "ACCEPT"], check=False)
    print(f"port-forwarding cert: serving for 3 minutes on port {port}")
    lan_ips = _detect_usable_ips()
    for ip in (lan_ips or ["<this machine's LAN IP>"]):
        print(f"  -> http://{ip}:{port}/")
    print("Open that URL in Safari on your iPhone. Ctrl-C to stop early.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        subprocess.run([IPTABLES, "-D", "INPUT", "-p", "tcp", "--dport", str(port), "-j", "ACCEPT"], check=False)
