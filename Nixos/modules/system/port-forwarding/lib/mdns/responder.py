import socket
import struct
import sys
import time
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import MCAST_GRP, MCAST_PORT, NAME, TTL, build_response, parse_questions


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
        print(f"[mdns {NAME}] send error ({what}, non-fatal): {e}", file=sys.stderr, flush=True)


def main():
    name = NAME if NAME.endswith(".local") else NAME + ".local"
    ip = detect_ip()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    sock.bind(("0.0.0.0", MCAST_PORT))

    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)

    print(f"[mdns {NAME}] advertising {name} -> {ip}", flush=True)
    send(sock, build_response(0, name, ip), "startup announce")

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
                        print(f"[mdns {NAME}] IP changed: {ip} -> {new_ip}", flush=True)
                        ip = new_ip
                except OSError as e:
                    print(f"[mdns {NAME}] IP re-detect failed (non-fatal): {e}", file=sys.stderr, flush=True)
                send(sock, build_response(0, name, ip), "periodic re-announce")
                last_announce = time.monotonic()
            continue
        except OSError as e:
            print(f"[mdns {NAME}] recv error (non-fatal): {e}", file=sys.stderr, flush=True)
            continue

        try:
            qr = (data[2] >> 7) & 1
        except IndexError:
            continue
        if qr != 0:
            continue

        questions = parse_questions(data)
        matched = [qu for (q, qu) in questions if q.lower() == name.lower()]
        if matched:
            query_id = struct.unpack(">H", data[0:2])[0]
            # Unicast straight back to the querier if any matching
            # question asked for it (QU) -- multicast otherwise, same
            # as before. addr is recvfrom's own (ip, port) -- already
            # exactly the reply destination a QU query wants.
            dest = addr if any(matched) else None
            send(sock, build_response(query_id, name, ip), "query response", dest)


if __name__ == "__main__":
    main()
