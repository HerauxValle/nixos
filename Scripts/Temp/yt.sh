#!/usr/bin/env bash
set -euo pipefail

COOKIE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/yt/cookies.txt"

usage() {
  echo "usage: yt.sh <login|logout|search TERM [--results N]|play ID>"
  exit 1
}

[ $# -ge 1 ] || usage

cmd="$1"; shift

case "$cmd" in
  login)
    mkdir -p "$(dirname "$COOKIE_FILE")"
    yt-dlp --cookies-from-browser firefox --cookies "$COOKIE_FILE" --skip-download --simulate ytsearch1:test
    echo "cookies exported to $COOKIE_FILE"
    ;;
  logout)
    rm -f "$COOKIE_FILE"
    ;;
  search)
    term="${1:?need a search term}"; shift
    n=10
    [ "${1:-}" = "--results" ] && n="$2"
    args=(--flat-playlist --print "%(id)s | %(title)s | %(duration>%H:%M:%S)s")
    [ -f "$COOKIE_FILE" ] && args+=(--cookies "$COOKIE_FILE")
    yt-dlp "${args[@]}" "ytsearch${n}:${term}"
    ;;
  play)
    id="${1:?need a video id}"
    mpv "https://youtu.be/$id"
    ;;
  *)
    usage
    ;;
esac
