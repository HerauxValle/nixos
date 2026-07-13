{ }:

# Zero-CPU, event-driven wait for the backend's own listener to appear on
# PORT, before this bridge ever attempts its own bind -- ported from pmg's
# own watcher (~/Projects/PMG/pmg.py, "watcher (keeps DNAT in sync with the
# listener, zero polling)"), not a sleep/retry loop. Real bug this exists
# to fix: systemd's Wants=/After= only orders unit *start jobs* (for
# Type=simple, that means "the moment the process forked", not "the
# process finished its own startup and actually bound its port") -- a
# fixed delay or a busy-poll loop both work by accident, not by
# guarantee, and neither generalizes to every current and future backend
# regardless of how slow or fast its own startup happens to be.
#
# The kernel primitive: NETLINK_CONNECTOR's process-connector multicast
# group pushes a notification for every exec/exit on the WHOLE system
# (the same primitive `ss -E`/auditd-style tools use) -- subscribe once,
# then block on recv() (genuinely idle, zero CPU) until the kernel wakes
# this up. Each wakeup is cheap: one read of /proc/net/tcp[46] to check
# whether PORT is now in LISTEN state, for ANY process (no per-service
# knowledge needed -- pmg's own port_listeners() does the identical
# check for the identical reason). This isn't specific to any backend:
# it just watches for a port number, in a completely uniform way,
# whether that's stash, jellyfin, ollama, or a service that doesn't
# exist yet.

# syntax: python
''
  NETLINK_CONNECTOR = 11
  CN_IDX_PROC = 0x1
  CN_VAL_PROC = 0x1
  PROC_CN_MCAST_LISTEN = 1
  PROC_EVENT_EXEC = 0x00000002
  PROC_EVENT_EXIT = 0x80000000


  def _port_is_listening(port):
      hexport = f"{port:04X}"
      for path in ("/proc/net/tcp", "/proc/net/tcp6"):
          try:
              lines = open(path).read().splitlines()[1:]
          except OSError:
              continue
          for line in lines:
              parts = line.split()
              if len(parts) < 4 or parts[3] != "0A":  # 0A == TCP_LISTEN
                  continue
              local = parts[1]
              colon = local.rfind(":")
              if local[colon + 1:].upper() == hexport:
                  return True
      return False


  def _netlink_proc_connector():
      sock = socket.socket(socket.AF_NETLINK, socket.SOCK_DGRAM, NETLINK_CONNECTOR)
      try:
          sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
      except OSError:
          pass
      sock.bind((os.getpid(), CN_IDX_PROC))
      op = struct.pack("=i", PROC_CN_MCAST_LISTEN)
      cn_msg = struct.pack("=IIIIHH", CN_IDX_PROC, CN_VAL_PROC, 0, 0, len(op), 0) + op
      nlmsghdr = struct.pack("=IHHII", 16 + len(cn_msg), 3, 0, 0, os.getpid())
      sock.send(nlmsghdr + cn_msg)
      return sock


  def _wait_for_proc_event(sock):
      # ENOBUFS is normal under process churn (multicast netlink has no
      # flow control) -- not fatal, just means "something happened,
      # go recheck" instead of blocking further, same as pmg's own
      # handling.
      while True:
          try:
              data = sock.recv(1024)
          except OSError as e:
              if e.errno == errno.ENOBUFS:
                  return
              raise
          if len(data) < 40:
              continue
          what = struct.unpack_from("=I", data, 36)[0]
          if what in (PROC_EVENT_EXEC, PROC_EVENT_EXIT):
              return


  def wait_for_backend(port):
      if _port_is_listening(port):
          return
      sock = _netlink_proc_connector()
      try:
          while not _port_is_listening(port):
              _wait_for_proc_event(sock)
      finally:
          sock.close()
''
