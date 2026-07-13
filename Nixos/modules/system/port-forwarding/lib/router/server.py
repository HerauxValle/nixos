import socket
import ssl
import sys
import threading
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import REDIRECT_MODE, ROUTES, handle_connection


def main():
    https = "--https" in sys.argv[1:]
    port = 443 if https else 80

    ctx = None
    if https:
        cert_arg = sys.argv[sys.argv.index("--cert") + 1] if "--cert" in sys.argv else None
        key_arg = sys.argv[sys.argv.index("--key") + 1] if "--key" in sys.argv else None
        if not cert_arg or not key_arg:
            print("router: --https needs --cert <path> --key <path>", file=sys.stderr)
            sys.exit(1)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(certfile=cert_arg, keyfile=key_arg)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("0.0.0.0", port))
    except OSError as e:
        print(f"router: could not bind :{port}: {e}", file=sys.stderr, flush=True)
        sys.exit(1)
    srv.listen(128)
    mode = "https" if https else ("redirect" if REDIRECT_MODE else "byte-forwarding")
    print(f"router: listening on :{port} ({mode} mode), routes: {list(ROUTES.keys())}", flush=True)

    while True:
        try:
            raw, _ = srv.accept()
        except OSError:
            break
        if https:
            try:
                conn = ctx.wrap_socket(raw, server_side=True)
            except ssl.SSLError:
                raw.close()
                continue
        else:
            conn = raw
        threading.Thread(target=handle_connection, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
