# Editor/type-checker only -- never read by Nix or executed at runtime.
# ./default.nix concatenates ./preamble.nix's Nix-generated constants and
# every fragment in this directory into one script; each fragment below
# declares (under `if TYPE_CHECKING:`, which is always False at runtime)
# exactly the names it expects to already exist in that shared namespace,
# so a type checker looking at one fragment in isolation can resolve them.
import ssl
from typing import Optional

PORT: int
MODE: str
CERTFILE: Optional[str]
KEYFILE: Optional[str]
HTTP_REDIRECT: bool
TLS_CTX: Optional[ssl.SSLContext]


def make_tls_context() -> Optional[ssl.SSLContext]: ...
def wait_for_backend(port: int) -> None: ...
def relay(src, dst) -> None: ...
def rewrite_request(buf, client_ip, scheme): ...
def rewrite_response(resp_buf, orig_host, scheme): ...
def handle_connection(raw) -> None: ...
