{ cfg, jellyfinDataDir, waitForApi }:

# postStart step -- pushes an @import pointing at the theme server (see
# ./server.nix) into Jellyfin's own branding config, via its REST API.
# Ported from the old sync-theme-css.sh, verified against a real recovered
# branding.xml from the backup drive (confirmed the mechanism actually
# worked in practice: CustomCss already had the matching @import line).
# Only touches the one line referencing this theme server's own port --
# never clobbers any other @import/snippet added manually in the Custom
# CSS box.

let
  themeUrl = "http://${cfg.themeServer.publicHostname}:${toString cfg.themeServer.port}/theme.css";
in
''
  set -euo pipefail
  ${waitForApi}

  if ! wait_for_api; then
    echo "self-hosted-jellyfin-theme-sync: API did not become ready within 60s -- skipping" >&2
    exit 0
  fi

  KEY="$(api_key)"
  if [ -z "$KEY" ]; then
    echo "self-hosted-jellyfin-theme-sync: no admin API key available yet (log into the dashboard, or set JELLYFIN_API_KEY via secrets self-hosted jellyfin) -- skipping"
    exit 0
  fi

  python3 - "$(api_url)" "$KEY" "${themeUrl}" <<'PYEOF'
import json
import sys
import urllib.request

base_url, key, theme_url = sys.argv[1], sys.argv[2], sys.argv[3]
endpoint = f"{base_url}/System/Configuration/branding"
headers = {"Authorization": f'MediaBrowser Token="{key}"', "Content-Type": "application/json"}

req = urllib.request.Request(endpoint, headers=headers)
with urllib.request.urlopen(req, timeout=10) as resp:
    branding = json.load(resp)

current_css = branding.get("CustomCss") or ""
import_line = f'@import url("{theme_url}");'

port = theme_url.rsplit(":", 1)[-1].split("/", 1)[0]
lines = current_css.splitlines()
kept = [l for l in lines if f":{port}/theme.css" not in l]

if import_line in lines and len(kept) == len(lines):
    print(f"self-hosted-jellyfin-theme-sync: already up to date -> {theme_url}")
    sys.exit(0)

new_css = "\n".join([import_line] + kept).strip()
branding["CustomCss"] = new_css

body = json.dumps(branding).encode()
req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
with urllib.request.urlopen(req, timeout=10) as resp:
    resp.read()

print(f"self-hosted-jellyfin-theme-sync: branding CustomCss updated -> {theme_url}")
PYEOF
''
