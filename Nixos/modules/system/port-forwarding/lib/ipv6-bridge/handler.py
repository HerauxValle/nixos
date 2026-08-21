# &desc: "Negotiates optional TLS handshakes, performs path redirects, and coordinates low-level HTTP header transformations."

import socket
import ssl
import sys
import threading
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import HTTP_REDIRECT, MODE, PORT, TLS_CTX, relay, rewrite_request, rewrite_response


def handle_connection(raw):
    conn = raw
    backend = None
    try:
        scheme = "http"
        if MODE == "https":
            if TLS_CTX is None:
                return
            try:
                conn = TLS_CTX.wrap_socket(raw, server_side=True)
                scheme = "https"
            except ssl.SSLError:
                return
        elif MODE == "http/s" and TLS_CTX is not None:
            try:
                first = raw.recv(1, socket.MSG_PEEK)
            except OSError:
                return
            if first == b"\x16":
                try:
                    conn = TLS_CTX.wrap_socket(raw, server_side=True)
                    scheme = "https"
                except ssl.SSLError:
                    return

        try:
            client_ip = raw.getpeername()[0]
        except OSError:
            client_ip = "unknown"

        buf = b""
        conn.settimeout(10)
        try:
            while b"\r\n\r\n" not in buf and len(buf) < 65536:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buf += chunk
        except (OSError, ssl.SSLError):
            pass
        if not buf:
            return
        conn.settimeout(None)

        new_req, tail, orig_host, req_path, is_long_lived = rewrite_request(buf, client_ip, scheme)

        if scheme == "http" and TLS_CTX is not None and HTTP_REDIRECT:
            target = b"https://" + (orig_host or f"[::1]:{PORT}".encode()) + req_path
            conn.sendall(
                b"HTTP/1.1 301 Moved Permanently\r\nLocation: " + target +
                b"\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
            )
            return

        backend = socket.create_connection(("127.0.0.1", PORT), timeout=10)
        backend.sendall(new_req if tail else buf)

        t1 = threading.Thread(target=relay, args=(conn, backend), daemon=True)
        t1.start()

        resp_buf = b""
        backend.settimeout(30)
        try:
            while b"\r\n\r\n" not in resp_buf and len(resp_buf) < 65536:
                chunk = backend.recv(4096)
                if not chunk:
                    break
                resp_buf += chunk
        except OSError:
            pass
        backend.settimeout(None)

        if resp_buf:
            conn.sendall(rewrite_response(resp_buf, orig_host, scheme))

        t2 = threading.Thread(target=relay, args=(backend, conn), daemon=True)
        t2.start()
        t1.join()
        t2.join()
    except Exception as exc:
        print(f"[bridge6 {PORT}] handle_connection: {exc!r}", file=sys.stderr, flush=True)
    finally:
        try:
            conn.close()
        except OSError:
            pass
        if backend is not None:
            try:
                backend.close()
            except OSError:
                pass
