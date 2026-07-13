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
      try:
          qdcount = struct.unpack(">H", data[4:6])[0]
      except Exception:
          return []
      offset = 12
      names = []
      for _ in range(qdcount):
          try:
              name, offset = parse_name(data, offset)
              offset += 4  # skip QTYPE + QCLASS
              names.append(name)
          except Exception:
              break
      return names


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
