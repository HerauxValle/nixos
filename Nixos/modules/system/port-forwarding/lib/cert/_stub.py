# Editor/type-checker only -- never read by Nix or executed at runtime.
# ./default.nix concatenates ./preamble.nix's Nix-generated constants and
# every fragment in this directory into one script; each fragment below
# declares (under `if TYPE_CHECKING:`, which is always False at runtime)
# exactly the names it expects to already exist in that shared namespace,
# so a type checker looking at one fragment in isolation can resolve them.
from pathlib import Path
from typing import List

CERT_DIR: Path
CA_FILE: Path
CA_KEY: Path
CERT_FILE: Path
KEY_FILE: Path
DNS_NAMES: List[str]
IPTABLES: str


def which(cmd: str) -> bool: ...
def ensure_ca() -> "tuple[Path, Path]": ...
def ensure_leaf() -> "tuple[Path, Path]": ...
def cert_serve(port: int = 4321) -> None: ...
