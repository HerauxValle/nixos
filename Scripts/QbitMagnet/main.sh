#!/usr/bin/env bash
# &desc: "x-scheme-handler/magnet target -- POSTs the magnet URI straight to qBittorrent's WebUI API (localhost:7080, LocalHostAuth=false) instead of launching a second, unrelated qBittorrent GUI instance."
set -euo pipefail

WEBUI="http://127.0.0.1:7080"

magnet="${1:-}"
if [ -z "$magnet" ]; then
    echo "usage: qbit-magnet <magnet-uri>" >&2
    exit 1
fi

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "qBittorrent" "$1"
}

response="$(curl -s -o /dev/null -w '%{http_code}' "$WEBUI/api/v2/torrents/add" --data-urlencode "urls=$magnet")" || {
    notify "couldn't reach qBittorrent's WebUI at $WEBUI"
    echo "[x] couldn't reach $WEBUI" >&2
    exit 1
}

if [ "$response" = "200" ]; then
    notify "magnet link added"
else
    notify "qBittorrent rejected the magnet link (HTTP $response)"
    echo "[x] qBittorrent WebUI returned HTTP $response" >&2
    exit 1
fi
