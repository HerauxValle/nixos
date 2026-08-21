# &desc: "Generates an operational server-side SSLContext sequence enforcing localized certificate pairs and HTTP/1.1 ALPN."

import ssl
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import CERTFILE, KEYFILE, MODE


def make_tls_context():
    if MODE not in ("https", "http/s") or not CERTFILE or not KEYFILE:
        return None
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERTFILE, KEYFILE)
    ctx.set_alpn_protocols(["http/1.1"])
    return ctx
