{ }:

# Just enough DNS packet encode/decode to answer one A-record question
# -- mirrors pmg's own mdns_responder.py byte-for-byte (same wire
# format, same cache-flush bit convention), just split out from the
# socket-handling loop in ./responder.nix.

# syntax: python
''
  def encode_name(name):
      out = b""
      for label in name.strip(".").split("."):
          out += bytes([len(label)]) + label.encode()
      return out + b"\x00"


  def parse_name(data, offset):
      labels = []
      seen_pointer = False
      start = offset
      while True:
          length = data[offset]
          if length == 0:
              offset += 1
              break
          if length & 0xC0 == 0xC0:
              pointer = ((length & 0x3F) << 8) | data[offset + 1]
              if not seen_pointer:
                  start = offset + 2
              offset = pointer
              seen_pointer = True
              continue
          offset += 1
          labels.append(data[offset:offset + length].decode(errors="replace"))
          offset += length
      end = start if seen_pointer else offset
      return ".".join(labels), end


  def parse_questions(data):
      # Returns (name, qu) pairs, not just names -- qu is RFC 6762 5.4's
      # "QU" bit, the top bit of QCLASS: a client sets it to ask for a
      # direct unicast reply instead of the usual multicast one. Real
      # bug this was added to fix: nss-mdns's own minimal NSS resolver
      # (glibc's mdns4_minimal, exactly what this module's own
      # nsswitch.conf wiring uses) always sets this bit and never joins
      # the multicast group at all -- ignoring it here made every
      # *.local lookup through nss-mdns silently time out even though
      # the responder was demonstrably answering multicast-joined
      # clients (e.g. avahi-browse) correctly the whole time.
      try:
          qdcount = struct.unpack(">H", data[4:6])[0]
      except Exception:
          return []
      offset = 12
      questions = []
      for _ in range(qdcount):
          try:
              name, offset = parse_name(data, offset)
              qclass = struct.unpack(">H", data[offset + 2:offset + 4])[0]
              qu = bool(qclass & 0x8000)
              offset += 4  # skip QTYPE + QCLASS
              questions.append((name, qu))
          except Exception:
              break
      return questions


  def build_response(query_id, name, ip):
      flags = 0x8400  # QR=1, opcode=0, AA=1
      header = struct.pack(">HHHHHH", query_id, flags, 0, 1, 0, 0)
      answer = (
          encode_name(name)
          + struct.pack(">H", 1)        # TYPE A
          + struct.pack(">H", 0x8001)   # CLASS IN | cache-flush bit (mDNS convention)
          + struct.pack(">I", TTL)
          + struct.pack(">H", 4)
          + socket.inet_aton(ip)
      )
      return header + answer
''
