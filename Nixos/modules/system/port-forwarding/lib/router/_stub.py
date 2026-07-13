# Editor/type-checker only -- never read by Nix or executed at runtime.
# ./default.nix concatenates ./preamble.nix's Nix-generated constants and
# every fragment in this directory into one script; each fragment below
# declares (under `if TYPE_CHECKING:`, which is always False at runtime)
# exactly the names it expects to already exist in that shared namespace,
# so a type checker looking at one fragment in isolation can resolve them.
from typing import Dict

ROUTES: Dict[str, int]
REDIRECT_MODE: bool


def handle_connection(conn) -> None: ...
