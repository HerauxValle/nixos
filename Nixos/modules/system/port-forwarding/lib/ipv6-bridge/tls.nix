{ }:

# TLS context setup -- mirrors pmg's own cmd_bridge6 preamble (tls_ctx
# creation before the accept loop starts). "https" always wraps every
# connection; "http/s" only wraps when the handler's own SNI peek (see
# handler.nix) sees a TLS ClientHello first.

# syntax: python
''
  def make_tls_context():
      if MODE not in ("https", "http/s") or not CERTFILE or not KEYFILE:
          return None
      ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
      ctx.load_cert_chain(CERTFILE, KEYFILE)
      ctx.set_alpn_protocols(["http/1.1"])
      return ctx
''
