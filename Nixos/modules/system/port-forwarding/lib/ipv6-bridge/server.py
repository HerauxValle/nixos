# &desc: "Initializes a dedicated IPv6 socket listener that gracefully exits if the target backend already binds dual-stack interfaces."

import errno
import socket
import sys
import threading
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import MODE, PORT, handle_connection, make_tls_context, wait_for_backend

TLS_CTX = make_tls_context()

def main():
    # Zero-CPU wait for the backend's own listener on PORT -- see
    # ./wait-backend.py. Guarantees the backend's own bind (dual-stack
    # or not) has already happened by the time we attempt ours, every
    # single start, regardless of which backend this is or how long
    # its own startup takes.
    wait_for_backend(PORT)

    srv = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    try:
        srv.bind(("::", PORT))
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            # The backend itself turned out to already be dual-stack
            # (confirmed real, not hypothetical: Go's net.Listen("tcp",
            # "0.0.0.0:PORT") -- stash, at least -- actually binds ONE
            # dual-stack [::]:PORT socket, IPV6_V6ONLY=0, that already
            # covers IPv6 itself). wait_for_backend above already
            # guarantees the backend bound first, so this means IPv6 is
            # already served directly by the backend -- nothing left
            # for this bridge to do. Exit 0 (not the generic
            # sys.exit(1) below) so Restart=on-failure doesn't loop
            # forever retrying a bind that will never succeed.
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
