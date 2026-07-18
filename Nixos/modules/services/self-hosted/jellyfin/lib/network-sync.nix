# &desc: "Jellyfin network config sync -- pushes port to InternalHttpPort/PublicHttpPort via REST API, needs admin key."

{ cfg, jellyfinDataDir, waitForApi }:

# postStart step -- pushes cfg.port into Jellyfin's own network config via
# its REST API. Unlike Ollama/SearXNG, Jellyfin has no env var for this
# (confirmed by a real run: ASPNETCORE_URLS is explicitly ignored --
# "Overriding address(es) ... Binding to endpoints defined via
# IConfiguration ... instead") and no CLI flag either -- the only real
# mechanism is its own API (the same one its dashboard's Networking page
# uses), so this needs the live process up and an admin key, same
# constraints as theme-sync.nix/plugins-sync.nix. On a genuinely fresh
# install this means port can't actually apply until after the setup
# wizard is completed once and an admin key exists -- a real asymmetry
# against Ollama/SearXNG, which apply from the very first start.
#
# Only InternalHttpPort/PublicHttpPort are written -- there is no
# "bind address" field in Jellyfin's NetworkConfiguration at all
# (confirmed against a real recovered network.xml and Jellyfin's own
# startup log, which always shows "Kestrel is listening on 0.0.0.0"
# regardless of config). That's why this module has no `host` option for
# Jellyfin, unlike Ollama/SearXNG -- there's nothing real to point it at.

''
  set -euo pipefail
  ${waitForApi}

  if ! wait_for_api; then
    echo "self-hosted-jellyfin-network-sync: API did not become ready within 60s -- skipping" >&2
    exit 0
  fi

  KEY="$(api_key)"
  if [ -z "$KEY" ]; then
    echo "self-hosted-jellyfin-network-sync: no admin API key yet -- create one via Dashboard -> API Keys -> +, or set JELLYFIN_API_KEY via secrets self-hosted jellyfin (a regular user login does NOT create one) -- skipping"
    exit 0
  fi

  python3 - "$(api_url)" "$KEY" "${toString cfg.port}" <<'PYEOF'
import json
import sys
import urllib.request

base_url, key, port_str = sys.argv[1], sys.argv[2], sys.argv[3]
port = int(port_str)
endpoint = f"{base_url}/System/Configuration/network"
headers = {"Authorization": f'MediaBrowser Token="{key}"', "Content-Type": "application/json"}

req = urllib.request.Request(endpoint, headers=headers)
with urllib.request.urlopen(req, timeout=10) as resp:
    network = json.load(resp)

if network.get("InternalHttpPort") == port and network.get("PublicHttpPort") == port:
    print(f"self-hosted-jellyfin-network-sync: already up to date (port {port})")
    sys.exit(0)

network["InternalHttpPort"] = port
network["PublicHttpPort"] = port

body = json.dumps(network).encode()
req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
with urllib.request.urlopen(req, timeout=10) as resp:
    resp.read()

print(f"self-hosted-jellyfin-network-sync: port updated -> {port} (restart Jellyfin for Kestrel to actually rebind)")
PYEOF
''
