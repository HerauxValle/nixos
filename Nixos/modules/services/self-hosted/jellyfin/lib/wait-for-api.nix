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
# over the dynamic sqlite lookup (grab the most recently created key from
# the ApiKeys table directly).
#
# Neither path is "zero-setup" -- a real, earlier assumption here that
# turned out wrong on a real run: a regular admin *login* does NOT
# populate the ApiKeys table at all (confirmed: completed the setup
# wizard, logged in, actively browsed the library, and ApiKeys stayed
# genuinely empty). A dedicated key via Dashboard -> API Keys -> + is
# always required, whichever path you take -- the dynamic lookup only
# saves the extra `secrets self-hosted jellyfin` step once that key
# exists, it was never going to work purely from a login the way the old
# theme-sync.sh/rescan.sh's own comments implied either.

''
  # Two "data" levels, not one -- Jellyfin creates its own data/
  # subdirectory inside whatever --datadir it's given (jellyfinDataDir/data
  # here), so the real db is at jellyfinDataDir/data/data/jellyfin.db.
  # Documented in info.md's "The real database path has an extra data/
  # level" section, but this exact line was the one that had never
  # actually been fixed to match -- confirmed on a real run: api_key()
  # silently found nothing even with a real key sitting in the db,
  # because this path pointed at a file that doesn't exist.
  DB="${jellyfinDataDir}/data/data/jellyfin.db"
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
