# Editor/type-checker only -- never read by Nix or executed at runtime.
# ./default.nix concatenates ./preamble.nix's Nix-generated constants and
# every fragment in this directory into one script; each fragment below
# declares (under `if TYPE_CHECKING:`, which is always False at runtime)
# exactly the names it expects to already exist in that shared namespace,
# so a type checker looking at one fragment in isolation can resolve them.
MCAST_GRP: str
MCAST_PORT: int
TTL: int
NAME: str


def build_response(query_id: int, name: str, ip: str) -> bytes: ...
def parse_questions(data: bytes) -> "list[tuple[str, bool]]": ...
