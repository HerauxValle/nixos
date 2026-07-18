# &desc: "Parses incoming HTTP raw headers to extract host fields and performs either 301 redirects or socket connection relaying."

import socket
import threading
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import REDIRECT_MODE, ROUTES


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


def respond(conn, status, body):
    resp = (
        f"HTTP/1.1 {status}\r\nContent-Type: text/plain\r\n"
        f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n"
    ).encode() + body
    try:
        conn.sendall(resp)
    except OSError:
        pass


def handle_connection(conn):
    backend = None
    try:
        conn.settimeout(5)
        buf = b""
        while b"\r\n\r\n" not in buf and len(buf) < 8192:
            chunk = conn.recv(4096)
            if not chunk:
                break
            buf += chunk
        if not buf:
            return

        head = buf.split(b"\r\n\r\n", 1)[0]
        lines = head.split(b"\r\n")
        request_line = lines[0].decode(errors="replace") if lines else ""
        host = None
        for line in lines[1:]:
            if line.lower().startswith(b"host:"):
                host = line.split(b":", 1)[1].strip().decode(errors="replace")
                break
        if not host:
            return
        hostname = host.split(":")[0].lower()

        port = ROUTES.get(hostname)
        if port is None:
            respond(conn, "404 Not Found", b"no port-forwarding .local route for this host\n")
            return

        if REDIRECT_MODE:
            path = request_line.split(" ")[1] if len(request_line.split(" ")) >= 2 else "/"
            location = f"http://{hostname}:{port}{path}"
            try:
                conn.sendall(
                    f"HTTP/1.1 301 Moved Permanently\r\nLocation: {location}\r\nConnection: close\r\n\r\n".encode()
                )
            except OSError:
                pass
            return

        try:
            backend = socket.create_connection(("127.0.0.1", port), timeout=5)
        except OSError:
            respond(conn, "502 Bad Gateway", b"backend not reachable\n")
            return
        backend.sendall(buf)
        conn.settimeout(None)
        backend.settimeout(None)
        t1 = threading.Thread(target=relay, args=(conn, backend), daemon=True)
        t2 = threading.Thread(target=relay, args=(backend, conn), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()
    except OSError:
        pass
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
