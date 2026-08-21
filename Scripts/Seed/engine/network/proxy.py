"""
core/network/proxy.py — userspace TCP port forwarder
Spawned by sd run for each exposed port. Tracked via process manager.
Pure stdlib, no deps.
"""

import socket
import threading
import sys
import os


def _forward(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except Exception:
        pass
    finally:
        try: src.close()
        except Exception: pass
        try: dst.close()
        except Exception: pass


def _handle(client: socket.socket, target_host: str, target_port: int) -> None:
    import time
    server = None
    max_retries = 5
    for attempt in range(max_retries):
        try:
            server = socket.create_connection((target_host, target_port), timeout=2)
            break
        except Exception:
            if attempt < max_retries - 1:
                time.sleep(0.5)
            else:
                client.close()
                return
    t1 = threading.Thread(target=_forward, args=(client, server), daemon=True)
    t2 = threading.Thread(target=_forward, args=(server, client), daemon=True)
    t1.start(); t2.start()
    t1.join(); t2.join()


def serve(host_port: int, target_host: str, target_port: int) -> None:
    """Block, accepting connections on both IPv4+IPv6 and forwarding to target."""
    # bind IPv6 with IPV6_V6ONLY=0 → accepts both IPv4 and IPv6 on one socket
    srv = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
    srv.bind(("::", host_port))
    srv.listen(64)
    while True:
        try:
            client, _ = srv.accept()
            t = threading.Thread(target=_handle,
                                 args=(client, target_host, target_port),
                                 daemon=True)
            t.start()
        except Exception:
            break


if __name__ == "__main__":
    # called as: python3 proxy.py <host_port> <target_host> <target_port>
    serve(int(sys.argv[1]), sys.argv[2], int(sys.argv[3]))