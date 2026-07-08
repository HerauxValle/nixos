#!/usr/bin/env bash
DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
cmd="${1:-help}"
case "$cmd" in
    -h | --help) cmd="help" ;;
esac
shift || true
script="$DIR/cmd/${cmd}.sh"
[ ! -f "$script" ] && { echo "unknown command: $cmd" >&2; echo "run 'pacnix help' for usage" >&2; exit 1; }
exec bash "$script" "$@"
