{ cfg, jellyfinDataDir, waitForApi }:

# postStart step -- pushes theme.css's real content directly into
# Jellyfin's branding CustomCss, via its REST API. Embedded, not
# @import'd from a separate server -- CustomCss is served as part of
# Jellyfin's own response to every client, so this works from any device
# that can already reach Jellyfin at all (LAN, VPN, remote, doesn't
# matter), with zero DNS/mDNS/hostname dependency. Replaced the old
# separate-theme-server + @import design (see git history / this file's
# prior version) once that turned out to need infrastructure
# (jellyfin.local mDNS resolution) that doesn't exist yet.
#
# Marker-delimited, not a full CustomCss overwrite -- only the content
# between BEGIN/END markers is Nix-managed; anything added manually via
# the dashboard outside those markers survives untouched. Same
# "never clobber manual additions" principle the old sync-theme-css.sh's
# single-line @import replacement had, adapted to an embedded block
# instead of one line.

let
  cssPath = cfg.theme.cssPath;
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

  python3 - "$(api_url)" "$KEY" "${cssPath}" <<'PYEOF'
import json
import re
import sys
import urllib.request

base_url, key, css_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(css_path, "r", encoding="utf-8") as f:
    theme_css = f.read()

BEGIN = "/* BEGIN nix-managed theme (self-hosted-jellyfin) -- do not edit inside, changes here are overwritten every start */"
END = "/* END nix-managed theme (self-hosted-jellyfin) */"
block = f"{BEGIN}\n{theme_css}\n{END}"

endpoint = f"{base_url}/System/Configuration/branding"
headers = {"Authorization": f'MediaBrowser Token="{key}"', "Content-Type": "application/json"}

req = urllib.request.Request(endpoint, headers=headers)
with urllib.request.urlopen(req, timeout=10) as resp:
    branding = json.load(resp)

current_css = branding.get("CustomCss") or ""
pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.DOTALL)

if pattern.search(current_css):
    new_css = pattern.sub(block, current_css)
else:
    new_css = (current_css.rstrip() + "\n\n" + block).strip()

if new_css == current_css:
    print("self-hosted-jellyfin-theme-sync: already up to date")
    sys.exit(0)

branding["CustomCss"] = new_css

body = json.dumps(branding).encode()
req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
with urllib.request.urlopen(req, timeout=10) as resp:
    resp.read()

print(f"self-hosted-jellyfin-theme-sync: branding CustomCss updated ({len(theme_css)} bytes embedded)")
PYEOF
''
