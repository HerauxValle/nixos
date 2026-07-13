{ }:

# The actual responder loop -- mirrors pmg's own run()/main(): join the
# mDNS multicast group, announce once on startup, answer any query for
# NAME, and re-announce periodically (re-detecting the local IP each
# time, since it can drift after a DHCP renew/interface roam). Last
# fragment concatenated by ./default.nix, so it's the one that runs.

# syntax: python
''
  def detect_ip():
      with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
          s.connect(("8.8.8.8", 80))
          return s.getsockname()[0]


  def send(sock, payload, what):
      try:
          sock.sendto(payload, (MCAST_GRP, MCAST_PORT))
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
          if any(q.lower() == name.lower() for q in questions):
              query_id = struct.unpack(">H", data[0:2])[0]
              send(sock, build_response(query_id, name, ip), "query response")


  if __name__ == "__main__":
      main()
''
