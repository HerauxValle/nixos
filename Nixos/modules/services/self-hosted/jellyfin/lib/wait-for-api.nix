{ jellyfinDataDir }:

# Shared by theme/sync.nix and plugins-sync.nix -- both need the
# identical "wait for the live API, then get an admin key" preamble.
# Bounded poll (matches Ollama's sync.nix pattern): ExecStartPost fires
# right after fork/exec, not once Jellyfin is actually accepting
# connections.
#
# api_key() prefers $JELLYFIN_API_KEY (a real, manually-created Jellyfin
# API key -- Dashboard -> API Keys -> +, then `secrets self-hosted
# jellyfin` to set JELLYFIN_API_KEY, see jellyfin.nix's environmentFile)
# over the dynamic sqlite lookup (grab the most recently created session
# token) -- stable/explicit once set up, but zero-setup-required by
# default: works out of the box before you ever create a dedicated key,
# same as the old theme-sync.sh/rescan.sh did.

''
  DB="${jellyfinDataDir}/data/jellyfin.db"
  NET_XML="${jellyfinDataDir}/config/network.xml"

  get_port() {
    grep -oPm1 '(?<=<InternalHttpPort>)[0-9]+' "$NET_XML" 2>/dev/null || echo "8096"
  }
  api_url() { echo "http://localhost:$(get_port)"; }
  api_key() {
    if [ -n "''${JELLYFIN_API_KEY:-}" ]; then
      echo "$JELLYFIN_API_KEY"
    else
      sqlite3 "$DB" "SELECT AccessToken FROM ApiKeys ORDER BY DateCreated DESC LIMIT 1;" 2>/dev/null || true
    fi
  }
  wait_for_api() {
    local i=0
    while ! curl -sf "$(api_url)/System/Info/Public" >/dev/null 2>&1; do
      sleep 2
      i=$((i + 1))
      [ "$i" -gt 30 ] && return 1
    done
    return 0
  }
''
