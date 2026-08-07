# &desc: "Listens for multicast DNS queries and transmits unicast or multicast A record name advertisements for every configured name."

import socket
import struct
import sys
import time
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import MCAST_GRP, MCAST_PORT, NAMES, TTL, build_response, parse_questions


def detect_ip():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]


def send(sock, payload, what, dest=None):
    # dest=None (the startup/periodic announce case, and the multicast-
    # response query case) -- the usual (MCAST_GRP, MCAST_PORT). A real
    # (ip, port) here is a direct unicast reply, for a query that set
    # the QU bit (see parse_questions in ./dns-codec.py).
    if dest is None:
        dest = (MCAST_GRP, MCAST_PORT)
    try:
        sock.sendto(payload, dest)
    except OSError as e:
        print(f"[mdns] send error ({what}, non-fatal): {e}", file=sys.stderr, flush=True)


def announce(sock, names, ip, what):
    for name in names:
        send(sock, build_response(0, name, ip), what)


def main():
    names = [n if n.endswith(".local") else n + ".local" for n in NAMES]
    ip = detect_ip()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    sock.bind(("0.0.0.0", MCAST_PORT))

    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)

    print(f"[mdns] advertising {', '.join(names)} -> {ip}", flush=True)
    announce(sock, names, ip, "startup announce")

    last_announce = time.monotonic()
    sock.settimeout(1.0)
    while True:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            if time.monotonic() - last_announce > TTL / 2:
                try:
                    new_ip = detect_ip()
                    if new_ip != ip:
                        print(f"[mdns] IP changed: {ip} -> {new_ip}", flush=True)
                        ip = new_ip
                except OSError as e:
                    print(f"[mdns] IP re-detect failed (non-fatal): {e}", file=sys.stderr, flush=True)
                announce(sock, names, ip, "periodic re-announce")
                last_announce = time.monotonic()
            continue
        except OSError as e:
            print(f"[mdns] recv error (non-fatal): {e}", file=sys.stderr, flush=True)
            continue

        try:
            qr = (data[2] >> 7) & 1
        except IndexError:
            continue
        if qr != 0:
            continue

        query_id = struct.unpack(">H", data[0:2])[0]
        # One response per matching question -- a single query can ask
        # about more than one of this process's names at once (unusual,
        # but the old one-process-per-name code could only ever match
        # one name anyway, so this is strictly more correct, not just
        # equivalent).
        for q, qu in parse_questions(data):
            if q.lower() not in names:
                continue
            dest = addr if qu else None
            send(sock, build_response(query_id, q, ip), "query response", dest)


if __name__ == "__main__":
    main()
