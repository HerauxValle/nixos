# &desc: "Jellyfin database rescan action -- manual maintenance for stale Folder/Movie entries, stops/edits DB/restarts/triggers scan."

{ jellyfinDataDir }:

# @rescan action -- ported from the old rescan.sh, a real (if surgical)
# DB-repair tool for a specific past bug: stale Folder ancestor rows and
# Movie entries left over after a library path changed, which stop
# Jellyfin rediscovering them correctly. Not automatic, not run on every
# start -- a deliberate, by-hand maintenance action (systemctl start
# self-hosted-jellyfin@rescan), same as the old CLI's `--rescan`. Stops
# the live service, edits the db directly, restarts it, triggers a
# library scan via the API once it's back up.

''
  set -euo pipefail
  # Two "data" levels, not one -- see wait-for-api.nix's own comment for
  # the full explanation (same bug, found and fixed there first).
  DATA_DIR="${jellyfinDataDir}/data/data"
  CONFIG_DIR="${jellyfinDataDir}/config"
  DB="$DATA_DIR/jellyfin.db"
  MBLINK_ROOT="$DATA_DIR/root/default"
  NET_XML="$CONFIG_DIR/network.xml"

  get_port() {
    grep -oPm1 '(?<=<InternalHttpPort>)[0-9]+' "$NET_XML" 2>/dev/null || echo "8096"
  }
  api_url() { echo "http://localhost:$(get_port)"; }
  api_key() { sqlite3 "$DB" "SELECT AccessToken FROM ApiKeys ORDER BY DateCreated DESC LIMIT 1;" 2>/dev/null || true; }

  echo "self-hosted-jellyfin-rescan: stopping..."
  systemctl stop self-hosted-jellyfin || true

  mapfile -t roots < <(
    find "$MBLINK_ROOT" -name "Library.mblink" 2>/dev/null \
      | xargs -I{} cat {} 2>/dev/null | tr -d '[:space:]' | grep .
  )

  if [ "''${#roots[@]}" -eq 0 ]; then
    echo "self-hosted-jellyfin-rescan: no library roots found in $MBLINK_ROOT -- skipping DB fix" >&2
  else
    echo "self-hosted-jellyfin-rescan: library roots:"
    printf '  %s\n' "''${roots[@]}"

    conditions=()
    for root in "''${roots[@]}"; do
      escaped="''${root//%/\\%}"
      escaped="''${escaped//_/\\_}"
      conditions+=("(Path = '$root' OR Path LIKE '$escaped/%')")
    done
    in_clause="$(IFS=' OR '; echo "''${conditions[*]}")"

    echo "self-hosted-jellyfin-rescan: cleaning stale ancestors and clearing movies for rediscovery..."
    sqlite3 "$DB" "
DELETE FROM BaseItems
WHERE Type = 'MediaBrowser.Controller.Entities.Folder'
  AND NOT ($in_clause);
SELECT changes() || ' stale folder rows removed';

DELETE FROM BaseItems
WHERE Type = 'MediaBrowser.Controller.Entities.Movies.Movie'
  AND ($in_clause);
SELECT changes() || ' movie rows cleared for rediscovery';"
  fi

  echo "self-hosted-jellyfin-rescan: starting..."
  systemctl start self-hosted-jellyfin

  echo "self-hosted-jellyfin-rescan: waiting for API..."
  i=0
  while ! curl -sf "$(api_url)/System/Info/Public" >/dev/null 2>&1; do
    sleep 2
    i=$((i + 1))
    if [ "$i" -gt 30 ]; then
      echo "self-hosted-jellyfin-rescan: timed out waiting for Jellyfin" >&2
      exit 1
    fi
  done

  KEY="$(api_key)"
  if [ -z "$KEY" ]; then
    echo "self-hosted-jellyfin-rescan: no API key found -- skipping scan trigger (run manually from the UI)"
    exit 0
  fi

  task_id="$(
    curl -sf "$(api_url)/ScheduledTasks" -H "Authorization: MediaBrowser Token=\"$KEY\"" \
      | python3 -c "
import sys, json
for t in json.load(sys.stdin):
    if t['Name'] == 'Scan Media Library':
        print(t['Id'])
        break
" 2>/dev/null || true
  )"

  if [ -z "$task_id" ]; then
    echo "self-hosted-jellyfin-rescan: could not find scan task ID -- skipping"
    exit 0
  fi

  curl -sf -X POST "$(api_url)/ScheduledTasks/Running/$task_id" -H "Authorization: MediaBrowser Token=\"$KEY\"" >/dev/null
  echo "self-hosted-jellyfin-rescan: library scan triggered (task $task_id) -- check the Movies library in the UI"
''
